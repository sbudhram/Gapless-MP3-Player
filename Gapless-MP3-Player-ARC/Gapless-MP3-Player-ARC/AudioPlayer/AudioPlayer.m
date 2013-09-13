//
//  AudioPlayer.m
//  Gapless-MP3-Player-ARC
//
//  Created by Kostya Teterin on 8/24/13.
//  Copyright (c) 2013 Kostya Teterin. All rights reserved.
//

#import "AudioPlayer.h"
#import "AudioSound.h"
#import "AudioPlayerUtilities.h"

@implementation AudioPlayer

/////////////////////////////////////////
//  Create audio player

static AudioPlayer *sharedAudioPlayer = nil;

+ (AudioPlayer *)defaultPlayer
{
    if(sharedAudioPlayer != nil) return sharedAudioPlayer;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedAudioPlayer = [[AudioPlayer alloc] init];
    });
    return sharedAudioPlayer;
}

- (id)init
{
    self = [super init];
    
    self.soundQueue = [[NSMutableArray alloc] initWithCapacity:3];
    self.queue = nil;
    self.volume = 1.0f;
    self.mMasterVolume = 1.0f;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stop) name:APEVENT_QUEUE_DONE object:self];
    return self;
}

- (void)dealloc
{
    if(_mFadeTimer)
    {
        [_mFadeTimer invalidate];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self clearQueue];
}

// Manage audio queue
- (void)addSoundFromFile:(NSString*)filename
{
    [self addSoundFromFile:filename loop:0];
}

- (void)addSoundFromFile:(NSString*)filename loop:(int)loop
{
    [self addSoundFromFile:filename loop:loop seek:0.0];
}

- (void)addSoundFromFile:(NSString*)filename loop:(int)loop seek:(double)time
{
    AudioSound *sound = [[AudioSound alloc] initWithSoundFile:filename];
    [self addSound:sound loop:loop seek:time];
}

- (void)addSound:(AudioSound*)sound;
{
    [self addSound:sound loop:0];
}

- (void)addSound:(AudioSound*)sound loop:(int)loop;
{
    [self addSound:sound loop:loop seek:0.0];
}

- (void)addSound:(AudioSound*)sound loop:(int)loop seek:(double)time
{
    //Build our queue element
    sound.loopCount = loop;
    
    //Seek to the time offset
    [sound seekToTime:time];
    
    [_soundQueue addObject:sound];
}

- (void)clearQueue
{

    // Clear sound queue
    [_soundQueue removeAllObjects];
}

// Control player
- (void)playQueue
{
    if(_queue != nil) return; // Another queue is already playing
    if(_soundQueue.count == 0) return; // No sounds in the queue
    
    if(_mFadeTimer)
    {
        [_mFadeTimer invalidate];
        self.mFadeTimer = nil;
    }
        
    // Check if all sounds in the queue have the same format and parameters
    AudioStreamBasicDescription *ethalonDesc = &self.currentSound.description->dataFormat;
    for (AudioSound *item in _soundQueue) {
        AudioStreamBasicDescription *desc = &item.description->dataFormat;
        bool isNotSame = NO;
        isNotSame |= (desc->mBytesPerFrame != ethalonDesc->mBytesPerFrame);
        isNotSame |= (desc->mBytesPerPacket != ethalonDesc->mBytesPerPacket);
        isNotSame |= (desc->mChannelsPerFrame != ethalonDesc->mChannelsPerFrame);
        isNotSame |= (desc->mFormatFlags != ethalonDesc->mFormatFlags);
        isNotSame |= (desc->mFormatID != ethalonDesc->mFormatID);
        isNotSame |= (desc->mSampleRate != ethalonDesc->mSampleRate);
        isNotSame |= (desc->mFramesPerPacket != ethalonDesc->mFramesPerPacket);
        if(isNotSame)
        {
            NSLog(@"Sound in the queue is different from the rest. Can't play the queue.");
            return;
        }
        
        //Otherwise, it is valid.  Rewind to start.
        item.description->packetPosition = 0;
    }
    
    CheckError(AudioQueueNewOutput(ethalonDesc, AQOutputCallback, (__bridge void *)(self), NULL, NULL, 0, &_queue), "AudioQueueNewOutput failed");
    
    // Add the callback that will determine when sound playing stop
    CheckError(AudioQueueAddPropertyListener(_queue, kAudioQueueProperty_IsRunning, AQPropertyListenerProc, (__bridge void *)(self)), "AudioQueueAddPropertyListener failed");
    
    
    // Copy magic cookie from file (it is providing a valuable information for the decoder)
    CopyEncoderCookieToQueue(currentSoundDescription(self)->playbackFile, _queue);
    
    // Allocate bufers and fill them with data by using the callback that is reading portions of file from the disk.
    AudioQueueBufferRef buffers[kNumberPlaybackBuffers];
    int i;
    for(i = 0; i < kNumberPlaybackBuffers; ++i)
    {
        CheckError(AudioQueueAllocateBuffer(_queue, currentSoundDescription(self)->bufferByteSize, &buffers[i]), "AudioQueueAllocateBuffer failed");
        AQOutputCallback((__bridge void *)(self), _queue, buffers[i]);
    }
    
    // Set audio queue volume
    AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, _mMasterVolume*_volume);
    
    // Play
    CheckError(AudioQueueStart(_queue, NULL), "AudioQueueStart failed");
    _isPlaying = YES;
}
- (void)stop
{
    NSLock *lock = [[NSLock alloc] init];
    if([lock tryLock])
    {
        _isPlaying = NO;
        if(_queue == nil) return;

        CheckError(AudioQueueRemovePropertyListener(_queue, kAudioQueueProperty_IsRunning, AQPropertyListenerProc, (__bridge void *)(self)), "AudioQueueRemovePropertyListener failed");
        CheckError(AudioQueueFlush(_queue), "AudioQueueFlush failed");
        CheckError(AudioQueueStop(_queue, YES), "AudioQueueStop failed");
 
        if(_mFadeTimer)
        {
            [_mFadeTimer invalidate];
            self.mFadeTimer = nil;
        }
        
        CheckError(AudioQueueDispose(_queue, YES), "AudioQueueDispose failed");
        self.queue = nil;
        [lock unlock];
    }
}

- (void)pause
{
    if(!_queue) return;
    _isPaused = YES;
    CheckError(AudioQueuePause(_queue), "AudioQueuePause failed");
}
- (void)resume
{
    if(!_queue) return;
    _isPaused = NO;
    CheckError(AudioQueueStart(_queue, nil), "AudioQueueStart (resume) failed");
}

- (void)breakLoop
{
    // Change the current element loop property so when it's done the next element will start to play
    currentAudioSound(self).loopCount = 0;
}

- (void)setVolume:(float)vol
{
    _volume = MAX(0, MIN(vol, 1));
    if(_isPlaying)
    {
        AudioQueueSetParameter(_queue, kAudioQueueParam_Volume, _mMasterVolume * _volume);
    }
}

- (void)fadeTo:(float)e_vol duration:(float)seconds
{
    [self fadeFrom:_volume to:e_vol duration:seconds];
}
- (void)fadeFrom:(float)s_vol to:(float)e_vol duration:(float)seconds
{
    self.mFadeSVol = s_vol;
    self.mFadeEVol = e_vol;
    self.mFadeSeconds = seconds;
    if(_mFadeTimer)
    {
        [_mFadeTimer invalidate];
        self.mFadeTimer = nil;
    }
    self.mFadeTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(onFadeTimer:) userInfo:nil repeats:YES];
   self.mTimestamp = [[NSDate date] timeIntervalSince1970];
}
- (void)onFadeTimer:(NSTimer*)timer
{
    NSTimeInterval interval = [[NSDate date] timeIntervalSince1970] - _mTimestamp;
    if(interval > _mFadeSeconds)
    {
        interval = _mFadeSeconds;
        [_mFadeTimer invalidate];
        self.mFadeTimer = nil;
    }
    
    [self setVolume:(_mFadeSVol + (_mFadeEVol-_mFadeSVol)*((float)interval/_mFadeSeconds))];
}

- (void)setMasterVolume:(float)volume
{
    _mMasterVolume = volume;
    _volume = volume;
}
- (float)getMasterVolume
{
    return _mMasterVolume;
}

-(AudioSound*)currentSound {
    if ([_soundQueue count]>0)
        return _soundQueue[0];
    else
        return nil;
}

@end
