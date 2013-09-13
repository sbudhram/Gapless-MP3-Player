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
    NSString *soundFile= [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:filename];
    CFURLRef soundURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)soundFile, kCFURLPOSIXPathStyle, false);
    CheckError(AudioFileOpenURL(soundURL, kAudioFileReadPermission, 0, &_soundDescription.playbackFile), "AudioFileOpenURL failed");
    CFRelease(soundURL);
    
    // Get file format information and check if it's compatible to play
    UInt32 propSize = sizeof(_soundDescription.dataFormat);
    CheckError(AudioFileGetProperty(_soundDescription.playbackFile, kAudioFilePropertyDataFormat, &propSize, &_soundDescription.dataFormat), "Couldn't get file's data format");
    
    // Get sound duration in seconds
    CFTimeInterval seconds;
    UInt32 propertySize = sizeof(seconds);
    AudioFileGetProperty(_soundDescription.playbackFile, kAudioFilePropertyEstimatedDuration, &propertySize, &seconds);
    self.mSoundDuration = seconds;
    
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
