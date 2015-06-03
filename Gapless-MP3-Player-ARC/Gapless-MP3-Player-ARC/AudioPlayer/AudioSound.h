//
//  AudioSound.h
//  Gapless-MP3-Player-ARC
//
//  Created by Kostya Teterin on 8/24/13.
//  Copyright (c) 2013 Kostya Teterin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AudioPlayerUtilities.h"

@class AudioPlayer;

@interface AudioSound : NSObject

@property (nonatomic) SoundDescription soundDescription;
@property (nonatomic) NSString *filename;
@property (nonatomic) Float64 mSoundDuration;
@property (nonatomic) SInt64 packetCount;
@property (nonatomic) NSUInteger loopCount;
@property (nonatomic) NSTimeInterval startTime;     //Start time relative to the start of the audio queue.  For looping tracks, resets with each loop.
@property (nonatomic) NSTimeInterval desiredStartTime; //If this is set, the queue will try to match it.

- (id)initWithSoundFile:(NSString*)filename;
- (void)loadSoundFile:(NSString*)filename;
-(void)seekToTime:(double)time;
- (SoundDescription*)sndDescription;
@end
