//
//  AudioPlayerUtilities.c
//  PuzzleFlow
//
//  Created by Shaun Budhram on 9/12/13.
//  Copyright (c) 2013 Shaun Budhram. All rights reserved.
//

#include <stdio.h>
#import "AudioPlayerUtilities.h"
#import "AudioSound.h"
#import "AudioPlayer.h"

// Just helper functions in case if the AudioSound format will be changed in the future (to store objects instead of structures for example)
AudioSound* currentAudioSound(AudioPlayer *player)
{
    return player.currentSound;
}

SoundDescription* currentSoundDescription(AudioPlayer *player)
{
    return currentAudioSound(player).sndDescription;
}

void CheckError(OSStatus error, const char *operation)
{
    if(error == noErr) return;
    
    char errorString[20];
    *(UInt32*)(errorString + 1) = CFSwapInt32HostToBig(error);
    if(isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4]))
    {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    }
    else
        sprintf(errorString, "%d", (int)error);
    
    NSLog(@"WARNING: Music: Error: %s (%s)\n", operation, errorString);

}

// Set up a "magic cookie" - a format related information for Audio Queue that helps to determine how to decode the audio data
void CopyEncoderCookieToQueue(AudioFileID theFile, AudioQueueRef queue)
{
    UInt32 propertySize;
    OSStatus result = AudioFileGetPropertyInfo(theFile, kAudioFilePropertyMagicCookieData, &propertySize, NULL);
    if(result == noErr && propertySize > 0)
    {
        Byte *magicCookie = (UInt8*)malloc(sizeof(UInt8) * propertySize);
        CheckError(AudioFileGetProperty(theFile, kAudioFilePropertyMagicCookieData, &propertySize, magicCookie), "Get cookie from file failed");
        CheckError(AudioQueueSetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, propertySize), "Set cookie on queue failed");
        free(magicCookie);
    }
}

void CalculateBytesForTime(AudioFileID inAudioFile, AudioStreamBasicDescription inDesc, Float64 inSeconds, UInt32 *outBufferSize, UInt32 *outNumPackets)
{
    UInt32 maxPacketSize;
    UInt32 propSize = sizeof(maxPacketSize);
    CheckError(AudioFileGetProperty(inAudioFile, kAudioFilePropertyPacketSizeUpperBound, &propSize, &maxPacketSize), "Couldn't get file's max packet size");
    
    static const int maxBufferSize = 0x10000;
    static const int minBufferSize = 0x4000;
    
    if(inDesc.mFramesPerPacket)
    {
        Float64 numPacketsForTime = inDesc.mSampleRate / inDesc.mFramesPerPacket * inSeconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    }
    else
    {
        *outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize:maxPacketSize;
    }
    
    if(*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize)
        *outBufferSize = maxBufferSize;
    else
    {
        if(*outBufferSize < minBufferSize) *outBufferSize = minBufferSize;
    }
    *outNumPackets = *outBufferSize / maxPacketSize;
}


// Callback when isRunning property is changed
void AQPropertyListenerProc (void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    UInt32 value;
    UInt32 size = sizeof(value);
    AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &value, &size);
    AudioPlayer *player = (__bridge AudioPlayer*)inUserData;
    if(value == 0)
    {
        // This event should be catched by audio player to dispose the audio queue
        [[NSNotificationCenter defaultCenter] postNotificationName:APEVENT_QUEUE_DONE object:player];
    }
}

// Callback that read the data to buffers and enqueue them to be played
void AQOutputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inCompleteAQBuffer)
{
    SoundDescription *sound = currentSoundDescription((__bridge AudioPlayer*)inUserData);
    if(sound == nil) return;
    
    UInt32 numBytes = inCompleteAQBuffer->mAudioDataBytesCapacity;
    UInt32 nPackets = sound->numPacketsToRead;

    CheckError(AudioFileReadPacketData(sound->playbackFile,
                                       false,
                                       &numBytes,
                                       sound->packetDescs,
                                       sound->packetPosition,
                                       &nPackets,
                                       inCompleteAQBuffer->mAudioData),
               "AudioFileReadPackets failed");

    AudioPlayer *player = (__bridge AudioPlayer*)inUserData;
    AudioSound *soundItem = currentAudioSound(player);
    
    if(nPackets > 0)
    {
        
        //If a desired start time value has been set, compare it to the current start time.
        //Adjust the packet position to account for this shift in time.
        if (soundItem.desiredStartTime != HUGE_VALF) {
            //Convert the time difference into packets and subtract the offset.
            NSTimeInterval secDiff = soundItem.startTime - soundItem.desiredStartTime;
            SInt64 packetDiff = (SInt64)round(secDiff * sound->dataFormat.mSampleRate / sound->dataFormat.mFramesPerPacket);
            SInt64 newPacketPos = sound->packetPosition += packetDiff;

            //If this packet position is less than 0 or greater than the number of packets in the sound,
            // cycle it.
            if (newPacketPos < 0)
                newPacketPos = soundItem.packetCount + newPacketPos;
            else if (newPacketPos >= soundItem.packetCount)
                newPacketPos = newPacketPos - soundItem.packetCount;
            
            sound->packetPosition = newPacketPos;
//            NSLog(@"*** TIME SHIFT DETECTED *** shifting by %f seconds (%lli packets)", secDiff, packetDiff);
            
            soundItem.desiredStartTime = HUGE_VALF;
        }
        
        // If there's more packets, read them
        inCompleteAQBuffer->mAudioDataByteSize = numBytes;
        AudioTimeStamp startTimestamp;
        AudioQueueEnqueueBufferWithParameters(inAQ,
                                              inCompleteAQBuffer,
                                              (sound->packetDescs?nPackets:0),
                                              sound->packetDescs,
                                              0,
                                              0,
                                              0,
                                              NULL,
                                              NULL,
                                              &startTimestamp);
        
        //Calculate the start time if the packet position is non-zero.
        NSTimeInterval secOffset = sound->packetPosition * sound->dataFormat.mFramesPerPacket / sound->dataFormat.mSampleRate;
        currentAudioSound(player).startTime = startTimestamp.mSampleTime / sound->dataFormat.mSampleRate - secOffset;
        
        sound->packetPosition += nPackets;
    }
    else
    {

        if(soundItem.loopCount == -1 || soundItem.loopCount > 0)
        {
            // If sound is done but it is looped, play it again
            sound->packetPosition = 0;
            AQOutputCallback(inUserData, inAQ, inCompleteAQBuffer);
            
            // If the loop isn't endless, decrease the counter
            if(soundItem.loopCount > 0) soundItem.loopCount -= 1;
        }
        else
        {
            // Move to the next sound (if any)
            NSUInteger index = [player currentItemNumber];
            if ([player.soundQueue count] > index+1) {

                player.currentSound = player.soundQueue[index+1];
                
                // Copy new magic cookie to the queue
                CopyEncoderCookieToQueue(currentSoundDescription(player)->playbackFile, inAQ);
                
                // Fill the buffers with the data of the next sound
                AQOutputCallback(inUserData, inAQ, inCompleteAQBuffer);
                [[NSNotificationCenter defaultCenter] postNotificationName:APEVENT_MOVING_TO_NEXT_SOUND object:player];
            }
            else
            {
                // Queue is done.
                CheckError(AudioQueueStop(inAQ, false), "AudioQueueStop failed");
            }
        }
    }
}
