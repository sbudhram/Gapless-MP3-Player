//
//  AudioPlayerUtilities.h
//  Gapless-MP3-Player-ARC
//
//  Created by Kostya Teterin on 8/24/13.
//  Copyright (c) 2013 Kostya Teterin. All rights reserved.
//

//
//  AudioPlayerUtilities.h
//  Gapless-MP3-Player
//
//  Created by Kostya Teterin on 18.05.12.
//  Copyright (c) 2012 Emotion Rays Entertainment. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

@class AudioPlayer;
@class AudioSound;

typedef struct SoundDescription {
    AudioFileID                     playbackFile;
    UInt32                          bufferByteSize;
    SInt64                          packetPosition;
    UInt32                          numPacketsToRead;
    AudioStreamPacketDescription    *packetDescs;
    AudioStreamBasicDescription     dataFormat;
} SoundDescription;

#define APEVENT_QUEUE_DONE  @"apeventQueueDone"
#define APEVENT_MOVING_TO_NEXT_SOUND  @"apeventMovingToNextSound"

// We will need 3 buffers: 1 is playing, 2 is reading and 3 in case of lag
#define kNumberPlaybackBuffers 3
#define kBufferSizeInSeconds 0.01

// Just helper functions in case if the AudioSound format will be changed in the future (to store objects instead of structures for example)
AudioSound* currentAudioSound(AudioPlayer *player);
SoundDescription* currentSoundDescription(AudioPlayer *player);

#pragma mark Utility functions

void CheckError(OSStatus error, const char *operation);
void CopyEncoderCookieToQueue(AudioFileID theFile, AudioQueueRef queue);
void CalculateBytesForTime(AudioFileID inAudioFile, AudioStreamBasicDescription inDesc, Float64 inSeconds, UInt32 *outBufferSize, UInt32 *outNumPackets);
void AQPropertyListenerProc (void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID);
void AQOutputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inCompleteAQBuffer);
