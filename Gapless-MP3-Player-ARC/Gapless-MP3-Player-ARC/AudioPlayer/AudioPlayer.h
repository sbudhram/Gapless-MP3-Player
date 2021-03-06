//
//  AudioPlayer.h
//  Gapless-MP3-Player-ARC
//
//  Created by Kostya Teterin on 8/24/13.
//  Copyright (c) 2013 Kostya Teterin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#import "AudioPlayerUtilities.h"
#import <OpenAL/al.h>
#import <OpenAL/alc.h> 

@class AudioSound;

#define AUDIO_PLAYER_EVENT_SOUND_DONE @"eventAudioPlayerSoundDone"] 

// There are some limitations on sound that should be played in a queue:
//    - They should have the same format
//    - Their internal structure should be the same

@interface AudioPlayer : NSObject

@property (nonatomic) AudioQueueRef queue;
@property (nonatomic) NSMutableArray *soundQueue;
@property (nonatomic) AudioSound *currentSound;
@property (nonatomic, readonly) BOOL isPaused;      //Paused by the user
@property (nonatomic, readonly) BOOL isPlaying;     //TRUE if if state is between playQueue and stop (even if audio is paused)
@property (nonatomic) float volume;

//Fade Parameters
@property (nonatomic) NSTimer *mFadeTimer;
@property (nonatomic) float mFadeSVol, mFadeEVol, mFadeSeconds;
@property (nonatomic) NSTimeInterval mTimestamp;
@property (nonatomic) float mMasterVolume;

// Create queue
+ (AudioPlayer*)defaultPlayer;

// Manage audio queue
// Loop indicates how many times to loop the segment (-1 == infinite)
// Seek is the number of seconds to offset into the segment for the initial playthrough.
//  It is an error if the seek offset is greater than the length of the segment.
- (void)addSoundFromFile:(NSString*)filename;
- (void)addSoundFromFile:(NSString*)filename loop:(int)loop;
- (void)addSoundFromFile:(NSString*)filename loop:(int)loop seek:(double)time;

// You can create AudioSound by yourself with these functions
- (void)addSound:(AudioSound*)sound;
- (void)addSound:(AudioSound*)sound loop:(int)loop;
- (void)addSound:(AudioSound*)sound loop:(int)loop seek:(double)time;

// Use this to update an existing sound in the queue to a specific play time.
// Only has an effect if a file with the given name is in the queue.
// Operates on the first file with this name encountered in the queue.
// ** NOTE: if this sound is currently playing, the effect is only heard when
// all existing buffers have been played.
- (BOOL)setSoundFromFile:(NSString*)filename loop:(int)loop seek:(double)time;

// Similar as above, but operates on a preexisting instance.
- (void)setSound:(AudioSound*)sound loop:(int)loop seek:(double)time;


- (void)clearQueue;

// Control player
- (void)playQueue;
- (void)prebufferQueue;
- (void)play;
- (void)stop;
- (void)pause;
- (void)resume;
- (void)breakLoop;

// Change sound volume over time
- (void)fadeFrom:(float)s_vol to:(float)e_vol duration:(float)seconds;
- (void)fadeTo:(float)e_vol duration:(float)seconds;

- (void)setMasterVolume:(float)_volume;
- (float)getMasterVolume;

//Get play information
- (NSUInteger)currentItemNumber;
- (NSTimeInterval)totalPlayTime;
- (NSTimeInterval)currentSoundPlayTime;


@end
