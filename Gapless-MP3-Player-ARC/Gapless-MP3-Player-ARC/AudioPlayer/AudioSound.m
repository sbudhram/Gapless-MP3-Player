//
//  AudioSound.m
//  Gapless-MP3-Player-ARC
//
//  Created by Kostya Teterin on 8/24/13.
//  Copyright (c) 2013 Kostya Teterin. All rights reserved.
//

#import "AudioSound.h"
#import "AudioPlayerUtilities.h"
#import <mach/mach_time.h>

@implementation AudioSound

- (id)initWithSoundFile:(NSString*)filename
{
    self = [super init];
    [self loadSoundFile:filename];
    return self;
}

- (void)loadSoundFile:(NSString*)filename
{
    self.filename = filename;
    
    NSString *soundFile= [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:filename];
    CFURLRef soundURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)soundFile, kCFURLPOSIXPathStyle, false);
    CheckError(AudioFileOpenURL(soundURL, kAudioFileReadPermission, 0, &_soundDescription.playbackFile), "AudioFileOpenURL failed");
    CFRelease(soundURL);
    
    // Get file format information and check if it's compatible to play
    UInt32 propSize = sizeof(_soundDescription.dataFormat);
    CheckError(AudioFileGetProperty(_soundDescription.playbackFile, kAudioFilePropertyDataFormat, &propSize, &_soundDescription.dataFormat), "Couldn't get file's data format");
    
    //Wrap into an extended AudioFile object
    ExtAudioFileRef exAudioFile;
    CheckError(ExtAudioFileWrapAudioFileID(_soundDescription.playbackFile, FALSE, &exAudioFile), "Could not create extended audio file object.");
    
    //Trigger a read of the the frame count - this is necessary to get an accurate duration time from the kAudioFilePropertyEstimatedDuration value.
    SInt64 frameCount;
    UInt32 propSizeFrames = sizeof(frameCount);
    CheckError(ExtAudioFileGetProperty(exAudioFile, kExtAudioFileProperty_FileLengthFrames, &propSizeFrames, &frameCount), "Could not get total frame count for file.");
    
    //Dispose of the extended file
    ExtAudioFileDispose(exAudioFile);
    
    // Get sound duration in seconds
    Float64 outDataSize = 0;
    UInt32 thePropSize = sizeof(Float64);
    AudioFileGetProperty(_soundDescription.playbackFile, kAudioFilePropertyEstimatedDuration, &thePropSize, &outDataSize);
    self.mSoundDuration = outDataSize;
    
    // Figure out how big data buffer we need and how much bytes will be reading on each callback
    CalculateBytesForTime(_soundDescription.playbackFile, _soundDescription.dataFormat, kBufferSizeInSeconds, &_soundDescription.bufferByteSize, &_soundDescription.numPacketsToRead);
    
    // Allocating memory for packet description array
    bool isFormatVBR = (_soundDescription.dataFormat.mBytesPerPacket == 0 || _soundDescription.dataFormat.mFramesPerPacket == 0);
    if(isFormatVBR)
        _soundDescription.packetDescs = (AudioStreamPacketDescription*)malloc(sizeof(AudioStreamPacketDescription) * _soundDescription.numPacketsToRead);
    else
        _soundDescription.packetDescs = NULL;
    
}

-(void)seekToTime:(double)seek {
    
    UInt64 totalPackets;
    UInt32 propertySize = sizeof(totalPackets);

    //Get the total number of packets in the file.
    AudioFileGetProperty(_soundDescription.playbackFile, kAudioFilePropertyAudioDataPacketCount, &propertySize, &totalPackets);
    
    Float64 mPacketsPerSecond = _soundDescription.dataFormat.mSampleRate / _soundDescription.dataFormat.mFramesPerPacket;
    Float64 packetsToTime = seek * mPacketsPerSecond;
    _soundDescription.packetPosition = (SInt64)round(packetsToTime) % totalPackets;
}

- (void)dealloc
{
    if(_soundDescription.packetDescs) free(_soundDescription.packetDescs);
    AudioFileClose(_soundDescription.playbackFile);
}

- (SoundDescription*)description
{
    return &_soundDescription;
}

@end
