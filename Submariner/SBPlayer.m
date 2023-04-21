//
//  SBPlayer.m
//  Sub
//
//  Created by Rafaël Warnault on 22/05/11.
//
//  Copyright (c) 2011-2014, Rafaël Warnault
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  * Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  * Neither the name of the Read-Write.fr nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#include <libkern/OSAtomic.h>
#include <AVFoundation/AVFoundation.h>

#import "SBClientController.h"
#import "SBAppDelegate.h"
#import "SBPlayer.h"
#import "SBTrack.h"
#import "SBEpisode.h"
#import "SBPodcast.h"
#import "SBServer.h"
#import "SBLibrary.h"
#import "SBCover.h"
#import "SBAlbum.h"

#import "NSURL+Parameters.h"
#import "NSManagedObjectContext+Fetch.h"

#import "Submariner-Swift.h"

#import <MediaPlayer/MPNowPlayingInfoCenter.h>
#import <MediaPlayer/MPMediaItem.h>

#import <MediaPlayer/MPRemoteCommandCenter.h>
#import <MediaPlayer/MPRemoteCommandEvent.h>
#import <MediaPlayer/MPRemoteCommand.h>


// notifications
NSString *SBPlayerPlaylistUpdatedNotification = @"SBPlayerPlaylistUpdatedNotification";
NSString *SBPlayerPlayStateNotification = @"SBPlayerPlayStateNotification";
NSString *SBPlayerMovieToPlayNotification = @"SBPlayerPlaylistUpdatedNotification";



@interface SBPlayer (Private)

- (void)playRemoteWithTrack:(SBTrack *)track;
- (void)playLocalWithURL:(NSURL *)url;
- (void)unplayAllTracks;
- (SBTrack *)getRandomTrackExceptingTrack:(SBTrack *)_track;
- (SBTrack *)nextTrack;
- (SBTrack *)prevTrack;
- (void)showVideoAlert;

@end

@implementation SBPlayer


@synthesize currentTrack;
@synthesize playlist;
@synthesize isShuffle;
@synthesize isPlaying;
@synthesize isPaused;
//@synthesize repeatMode;
@synthesize remotePlayer;




#pragma mark -
#pragma mark Singleton support 

+ (SBPlayer*)sharedInstance {

    static SBPlayer* sharedInstance = nil;
    if (sharedInstance == nil) {
        sharedInstance = [[SBPlayer alloc] init];
    }
    return sharedInstance;
    
}

- (void)initializeSystemMediaControls
{
    MPRemoteCommandCenter *remoteCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    
    // XXX: Update on new default write
    NSNumber *interval = [NSNumber numberWithFloat: [[NSUserDefaults standardUserDefaults] floatForKey:@"SkipIncrement"]];
    
    [remoteCommandCenter.playCommand setEnabled:YES];
    [remoteCommandCenter.pauseCommand setEnabled:YES];
    [remoteCommandCenter.togglePlayPauseCommand setEnabled:YES];
    [remoteCommandCenter.stopCommand setEnabled:YES];
    [remoteCommandCenter.changePlaybackPositionCommand setEnabled:YES];
    [remoteCommandCenter.nextTrackCommand setEnabled:YES];
    [remoteCommandCenter.previousTrackCommand setEnabled:YES];
    // Disable these because they get used instead of prev/next track on macOS, at least in 12.
    // XXX: Does it make more sense to bind seekForward/Backward? For podcasts?
    //[remoteCommandCenter.skipForwardCommand setEnabled:YES];
    //[remoteCommandCenter.skipBackwardCommand setEnabled:YES];
    remoteCommandCenter.skipForwardCommand.preferredIntervals = @[ interval ];
    remoteCommandCenter.skipBackwardCommand.preferredIntervals = @[ interval ];
    [remoteCommandCenter.ratingCommand setEnabled:YES];
    [remoteCommandCenter.ratingCommand setMinimumRating: 0.0];
    [remoteCommandCenter.ratingCommand setMaximumRating: 5.0];
    // XXX: Shuffle, repeat, maybe bookmark

    [[remoteCommandCenter playCommand] addTarget:self action:@selector(clickPlay)];
    [[remoteCommandCenter pauseCommand] addTarget:self action:@selector(clickPause)];
    [[remoteCommandCenter togglePlayPauseCommand] addTarget:self action:@selector(clickPlay)];
    [[remoteCommandCenter stopCommand] addTarget:self action:@selector(clickStop)];
    [[remoteCommandCenter changePlaybackPositionCommand] addTarget:self action:@selector(clickSeek:)];
    [[remoteCommandCenter nextTrackCommand] addTarget:self action:@selector(clickNext)];
    [[remoteCommandCenter previousTrackCommand] addTarget:self action:@selector(clickPrev)];
    // Disable at the selector level too.
    //[[remoteCommandCenter skipForwardCommand] addTarget:self action:@selector(clickSkipForward)];
    //[[remoteCommandCenter skipBackwardCommand] addTarget:self action:@selector(clickSkipBackward)];
    [[remoteCommandCenter ratingCommand] addTarget:self action:@selector(clickRating:)];
    
    songInfo = [[NSMutableDictionary alloc] init];
}

- (id)init {
    self = [super init];
    if (self) {
        remotePlayer = [[AVPlayer alloc] init];
        // This is counter-intuitive, but this has to be *off* for AirPlay from the app to work
        // per https://stackoverflow.com/a/29324777 - seems to cause problem for video, but
        // we don't care about video
        remotePlayer.allowsExternalPlayback = NO;
        
        // setup observers
        [remotePlayer addObserver:self forKeyPath: @"status" options: NSKeyValueObservingOptionNew context: nil];
        [remotePlayer addObserver:self forKeyPath: @"currentItem" options: NSKeyValueObservingOptionNew context: nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemDidFinishPlaying:) name:AVPlayerItemDidPlayToEndTimeNotification object: nil];
        
        playlist = [[NSMutableArray alloc] init];
        isShuffle = NO;
        isCaching = NO;
        
        repeatMode = SBPlayerRepeatNo;
    }
    [self initializeSystemMediaControls];
    [self initNotifications];
    return self;
}

- (void)dealloc {
    // remove observers
    [remotePlayer removeObserver:self forKeyPath:@"status" context:nil];
    [remotePlayer removeObserver:self forKeyPath:@"currentItem" context:nil];
    [[NSNotificationCenter defaultCenter] removeObserver: self name:AVPlayerItemDidPlayToEndTimeNotification object: nil];
    // remove remote player observers
    [self stop];
    
}

#pragma mark -
#pragma mark System Now Playing/Controls

// These two are separate because updating metadata is more expensive than i.e. seek position
-(void) updateSystemNowPlayingStatus  {
    MPNowPlayingInfoCenter * defaultCenter = [MPNowPlayingInfoCenter defaultCenter];
    
    SBTrack *currentTrack = [self currentTrack];
    
    if (currentTrack != nil) {
        // times are in sec; trust the SBTrack if the player isn't ready
        // as passing NaNs here will crash the menu bar (!)
        NSTimeInterval duration = [self durationTime];
        if (isnan(duration) || duration == 0) {
            [songInfo setObject: [NSNumber numberWithDouble: 0] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
            [songInfo setObject: [currentTrack duration] forKey:MPMediaItemPropertyPlaybackDuration];
        } else {
            [songInfo setObject: [NSNumber numberWithDouble: [self currentTime]] forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
            [songInfo setObject: [NSNumber numberWithDouble: duration] forKey:MPMediaItemPropertyPlaybackDuration];
        }
    } else {
        [songInfo removeObjectForKey: MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [songInfo removeObjectForKey: MPMediaItemPropertyPlaybackDuration];
    }
    
    if (![self isPaused] && [self isPlaying]) {
        [defaultCenter setPlaybackState:MPNowPlayingPlaybackStatePlaying];
    } else if ([self isPaused] && [self isPlaying]) {
        [defaultCenter setPlaybackState:MPNowPlayingPlaybackStatePaused];
    } else if (![self isPlaying]) {
        [defaultCenter setPlaybackState:MPNowPlayingPlaybackStateStopped];
    }
    [defaultCenter setNowPlayingInfo: songInfo];
}

-(void) updateSystemNowPlayingMetadataMusic: (SBTrack*)currentTrack {
    [songInfo setObject: [currentTrack albumString] forKey:MPMediaItemPropertyAlbumTitle];
    [songInfo setObject: currentTrack.artistName ?: currentTrack.artistString forKey:MPMediaItemPropertyArtist];
    NSString *genre = [currentTrack genre];
    if (genre != nil) {
        [songInfo setObject: genre forKey:MPMediaItemPropertyGenre];
    }
    NSNumber *discNumber = [currentTrack discNumber];
    if (discNumber != nil) {
        [songInfo setObject: discNumber forKey: MPMediaItemPropertyDiscNumber];
    }
    // do we have enough metadata to fill in?
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDate *releaseYear = [calendar dateWithEra:1 year:[[currentTrack year] intValue] month:0 day:0 hour:0 minute:0 second:0 nanosecond:0];
    [songInfo setObject:releaseYear forKey:MPMediaItemPropertyReleaseDate];
    // XXX: movieAttributes is blank and could be filled in with externalMetadata?
}

-(void) updateSystemNowPlayingMetadataPodcast: (SBEpisode*)currentTrack {
    // XXX: It seems there's the raw metadata Subsonic doesn't give us (i.e.
    // "BBC World Service" as underlying artist)
    [songInfo setObject: currentTrack.podcast.itemName forKey: MPMediaItemPropertyPodcastTitle];
    [songInfo setObject: currentTrack.artistName ?: currentTrack.artistString forKey:MPMediaItemPropertyArtist];
    NSDate *publishDate = currentTrack.publishDate;
    if (publishDate) {
        [songInfo setObject: publishDate forKey: MPMediaItemPropertyReleaseDate];
    } else {
        NSCalendar *calendar = [NSCalendar currentCalendar];
        NSDate *releaseYear = [calendar dateWithEra:1 year:[[currentTrack year] intValue] month:0 day:0 hour:0 minute:0 second:0 nanosecond:0];
        [songInfo setObject:releaseYear forKey:MPMediaItemPropertyReleaseDate];
    }
    return;
}

-(void) updateSystemNowPlayingMetadata {
    SBTrack *currentTrack = [self currentTrack];
    
    if (currentTrack != nil) {
        // i guess if we ever support video again...
        [songInfo setObject: [NSNumber numberWithInteger: MPNowPlayingInfoMediaTypeAudio] forKey:MPMediaItemPropertyMediaType];
        // XXX: podcasts will have different properties on SBTrack
        [songInfo setObject: [currentTrack itemName] forKey:MPMediaItemPropertyTitle];
        [songInfo setObject: [currentTrack rating] forKey:MPMediaItemPropertyRating];
        // seems the OS can use this to generate waveforms? should it be the download URL?
        [songInfo setObject:[currentTrack streamURL] forKey:MPMediaItemPropertyAssetURL];
        if ([currentTrack isKindOfClass: SBEpisode.class]) {
            [self updateSystemNowPlayingMetadataPodcast: (SBEpisode*)currentTrack];
        } else {
            [self updateSystemNowPlayingMetadataMusic: currentTrack];
        }
        if (@available(macOS 10.13.2, *)) {
            NSImage *artwork = [currentTrack coverImage];
            CGSize artworkSize = [artwork size];
            MPMediaItemArtwork *mpArtwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkSize requestHandler:^NSImage * _Nonnull(CGSize size) {
                return artwork;
            }];
            [songInfo setObject: mpArtwork forKey:MPMediaItemPropertyArtwork];
        }
    } else {
        [songInfo removeObjectForKey: MPMediaItemPropertyMediaType];
        [songInfo removeObjectForKey: MPMediaItemPropertyTitle];
        [songInfo removeObjectForKey: MPMediaItemPropertyAlbumTitle];
        [songInfo removeObjectForKey: MPMediaItemPropertyArtist];
        [songInfo removeObjectForKey: MPMediaItemPropertyGenre];
        [songInfo removeObjectForKey: MPMediaItemPropertyRating];
        [songInfo removeObjectForKey: MPMediaItemPropertyAssetURL];
        [songInfo removeObjectForKey: MPMediaItemPropertyReleaseDate];
        [songInfo removeObjectForKey: MPMediaItemPropertyArtwork];
    }
}

-(void) updateSystemNowPlaying {
    [self updateSystemNowPlayingMetadata];
    [self updateSystemNowPlayingStatus];
}

- (MPRemoteCommandHandlerStatus)clickPlay {
    // This is a toggle because the system media key always sends play.
    [self playPause];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickPause {
    [self pause];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickStop {
    [self stop];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickNext {
    [self next];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickPrev {
    [self previous];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickSeek: (MPChangePlaybackPositionCommandEvent*)event {
    if (self.isPlaying) {
        NSTimeInterval newTime = [event positionTime];
        [self seekToTime: newTime];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    return MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
}

- (MPRemoteCommandHandlerStatus)clickSkipForward {
    [self fastForward];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickSkipBackward {
    [self rewind];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)clickRating: (double)rating {
    if ([self currentTrack] != nil && [self currentTrack].server != nil) {
        [[self currentTrack] setRating: [NSNumber numberWithFloat: rating]];
        return MPRemoteCommandHandlerStatusSuccess;
    }
    return MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
}

#pragma mark -
#pragma mark User Notifications

- (void)initNotifications {
    UNUserNotificationCenter *centre = [UNUserNotificationCenter currentNotificationCenter];
    centre.delegate = self;
    // XXX: Do we need to do this after authorization?
    // Add a skip action, like AM
    UNNotificationAction *skipAction = [UNNotificationAction actionWithIdentifier: @"SubmarinerSkipAction" title: @"Skip" options: UNNotificationActionOptionNone];
    // This is the same as the notification identifier, because there's only one of those for now.
    UNNotificationCategory *nowPlayingCategory = [UNNotificationCategory categoryWithIdentifier: @"SubmarinerNowPlayingNotification" actions: @[skipAction] intentIdentifiers: @[] options: UNNotificationCategoryOptionNone];
    [centre setNotificationCategories: [NSSet setWithArray: @[nowPlayingCategory]]];
    // XXX: Make it so we store if we can post a notification instead of blindly firing.
    [centre getNotificationSettingsWithCompletionHandler: ^(UNNotificationSettings *settings) {
        switch (settings.authorizationStatus) {
            case UNAuthorizationStatusNotDetermined:
                [self requestNotificationPermissions];
                return;
            case UNAuthorizationStatusAuthorized:
                // we're good
                return;
            case UNAuthorizationStatusProvisional:
                return;
            case UNAuthorizationStatusDenied:
                return;
        }
    }];
}

- (void)requestNotificationPermissions {
    UNUserNotificationCenter *centre = [UNUserNotificationCenter currentNotificationCenter];
    // Requesting sound is unwanted when we're playing music.
    // Badge permissions might be useful, but we use badges for other things.
    [centre requestAuthorizationWithOptions: (UNAuthorizationOptionAlert) completionHandler: ^(BOOL granted, NSError * _Nullable error) {
        if (!granted) {
            NSLog(@"The user denied us permission. Oh well.");
            return;
        }
    }];
}

- (void)postNowPlayingNotification {
    SBTrack *currentTrack = [self currentTrack];
    if (currentTrack == nil) {
        return;
    }
    UNUserNotificationCenter *centre = [UNUserNotificationCenter currentNotificationCenter];
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.categoryIdentifier = @"SubmarinerNowPlayingNotification";
    // Apple Music uses this format as well; we don't need to indicate it's a now playing thing.
    content.title = [NSString stringWithFormat: @"%@", currentTrack.itemName];
    // Use an em dash like Apple Music
    content.body = [self subtitle];
    // Add a cover image, fetch from our local cache since this API won't take an NSImage
    // XXX: Fetch from SBAlbum. The cover in SBTrack is seemingly only used for requests.
    // This means there's also a bunch of empty dupe cover objects in the DB...
    SBCover *newCover = currentTrack.album.cover;
    NSString *coverPath = newCover.imagePath;
    if (coverPath != nil && [[NSFileManager defaultManager] fileExistsAtPath:coverPath]) {
        NSURL *coverUrl = [NSURL fileURLWithPath: coverPath];
        NSError *error = nil;
        // XXX: Should we use a persistent identifier? Manage a cache of attachments?
        UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier: @"" URL: coverUrl options: @{} error: &error];
        if (attachment != nil) {
            content.attachments = @[ attachment ];
        } else if (error != nil) {
            NSLog(@"Error making attachment: %@", error);
        }
    }
    // an interval of 0 faults
    UNNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval: 0.1 repeats: false];
    // The identifier being the same will coalesce all the now playing notifications.
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier: @"SubmarinerNowPlayingNotification" content: content trigger: trigger];
    [centre addNotificationRequest: request withCompletionHandler: ^(NSError * _Nullable error) {
        if (error != nil) {
            NSLog(@"Error posting now playing notification: %@", error);
        }
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    // We have to do this if we implement the delegate.
    // If we didn't assign a delegate, we basically get this behaviour,
    // but if we did assign the delegate and didn't implement this method,
    // it would always supress the notification (UNNotificationPresentationOptionNone).
    UNNotificationPresentationOptions opts = NSApplication.sharedApplication.isActive
        ? UNNotificationPresentationOptionList
        : UNNotificationPresentationOptionBanner;
    completionHandler(opts);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    // Select the currently playing track if it's a SubmarinerNowPlayingNotification.
    // We don't need to know the track, because the coalescing means we only current is relevant.
    if ([response.notification.request.identifier isEqualTo: @"SubmarinerNowPlayingNotification"]) {
        // Default, so not one of the buttons (if we have them or not)
        if ([response.actionIdentifier isEqualTo: UNNotificationDefaultActionIdentifier]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[SBAppDelegate sharedInstance] zoomDatabaseWindow: self];
                [[SBAppDelegate sharedInstance] goToCurrentTrack: self];
            });
        } else if ([response.actionIdentifier isEqualTo: @"SubmarinerSkipAction"]) {
            [self next];
        }
    }
    completionHandler();
}

#pragma mark -
#pragma mark Playlist Management

- (void)addTrack:(SBTrack *)track replace:(BOOL)replace {
    
    if(replace) {
        [playlist removeAllObjects];
    }
    
    [playlist addObject:track];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
}

- (void)addTrackArray:(NSArray<SBTrack*> *)array replace:(BOOL)replace {
    
    if(replace) {
        [playlist removeAllObjects];
    }
    
    [playlist addObjectsFromArray:array];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
}


- (void)removeTrack:(SBTrack *)track {
    if([track isEqualTo:self.currentTrack]) {
        [self stop];
    }
    
    [playlist removeObject:track];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
}

- (void)removeTrackArray:(NSArray<SBTrack*> *)tracks {
    NSUInteger playingTrackIndex = [tracks indexOfObjectPassingTest: ^BOOL (SBTrack *track, NSUInteger i, BOOL *stop) {
        BOOL isCurrentTrack = [track isEqualTo:self.currentTrack];
        if (isCurrentTrack) {
            *stop = YES;
        }
        return isCurrentTrack;
    }];
    if (playingTrackIndex != NSNotFound) {
        [self stop];
    }
    [playlist removeObjectsInArray:tracks];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
}


- (void)removeTrackIndexSet: (NSIndexSet*)tracks {
    NSUInteger playingTrackIndex = [tracks indexPassingTest: ^BOOL (NSUInteger i, BOOL *stop) {
        SBTrack *track = [playlist objectAtIndex: i];
        BOOL isCurrentTrack = [track isEqualTo:self.currentTrack];
        if (isCurrentTrack) {
            *stop = YES;
        }
        return isCurrentTrack;
    }];
    if (playingTrackIndex != NSNotFound) {
        [self stop];
    }
    [playlist removeObjectsAtIndexes: tracks];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
}



#pragma mark -
#pragma mark Player Control

- (void)playTrack:(SBTrack *)track {
    
    // stop player
    [self stop];
        
    // clean previous playing track
    if(self.currentTrack != nil) {
        [self.currentTrack setIsPlaying:[NSNumber numberWithBool:NO]];
        self.currentTrack = nil;
    }
    
    // set the new current track
    [self setCurrentTrack:track];
    
    // Caching is handled when we request it now, including its file name
    isCaching = NO;
    
    if(self.currentTrack.isVideo) {
        [self showVideoAlert];
        return;
    } else {
        [self playRemoteWithTrack:self.currentTrack];
    }
    
    // setup player for playing
    [self.currentTrack setIsPlaying:[NSNumber numberWithBool:YES]];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
    self.isPlaying = YES;
    self.isPaused = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlayStateNotification object:self];
    
    // update NPIC
    [self updateSystemNowPlaying];
    [self postNowPlayingNotification];

    // tell the server we're playing it, if applicable
    if (self.currentTrack.server != nil && [self.currentTrack.localTrack streamURL] != nil
        && [[NSUserDefaults standardUserDefaults] boolForKey:@"scrobbleToServer"] == YES) {
        [self.currentTrack.server.clientController scrobble: self.currentTrack.id];
    }
}


- (void)playRemoteWithTrack:(SBTrack *)track {
    [remotePlayer replaceCurrentItemWithPlayerItem:nil];
    
    NSURL *url = [self.currentTrack.localTrack streamURL];
    if (url == nil) {
        url = [self.currentTrack streamURL];
    }
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
        // Work around macOS not recognizing the right FLAC MIME type.
        @"AVURLAssetOutOfBandMIMETypeKey": [track macOSCompatibleContentType],
        // Fix inaccurate seeks for FLAC.
        AVURLAssetPreferPreciseDurationAndTimingKey: [NSNumber numberWithBool: YES]
    }];
    AVPlayerItem *newItem = [AVPlayerItem playerItemWithAsset:asset];

    [remotePlayer replaceCurrentItemWithPlayerItem: newItem];
    [remotePlayer setVolume:[self volume]];
    [remotePlayer play]; // needs a little help from us for next track
}


- (void) playTracklistAtBeginning {
    if ([playlist count] < 1) {
        return;
    }
    SBTrack *first = [playlist firstObject];
    [self playTrack: first];
}


- (void)playOrResume {
    if(remotePlayer != nil) {
        [remotePlayer play];
        self.isPaused = NO;
    }
    [self updateSystemNowPlaying];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlayStateNotification object:self];
}


- (void)pause {
    if(remotePlayer != nil) {
        [remotePlayer pause];
        self.isPaused = YES;
    }
    [self updateSystemNowPlayingStatus];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlayStateNotification object:self];
}


- (void)playPause {
    bool wasPlaying = self.isPlaying;
    if((remotePlayer != nil) && ([remotePlayer rate] != 0)) {
        [remotePlayer pause];
        self.isPaused = YES;
    } else {
        [remotePlayer play];
        self.isPaused = NO;
    }
    // if we weren't playing, we need to update the metadata
    if (wasPlaying) {
        [self updateSystemNowPlayingStatus];
    } else {
        [self updateSystemNowPlaying];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlayStateNotification object:self];
}


- (void)maybeDeleteCurrentTrack {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"deleteAfterPlay"]) {
        return;
    }
    SBTrack *current = [self currentTrack];
    [self removeTrack: current];
}


- (void)next {
    SBTrack *next = [self nextTrack];
    [self maybeDeleteCurrentTrack];
    if(next != nil) {
        @synchronized(self) {
            [self playTrack:next];
        }
    } else {
        [self stop];
    }
}

- (void)previous {
    SBTrack *prev = [self prevTrack];
    [self maybeDeleteCurrentTrack];
    if(prev != nil) {
        @synchronized(self) {
            //[self stop];
            [self playTrack:prev];
        }
    }
}


- (void)setVolume:(float)volume {
    
    [[NSUserDefaults standardUserDefaults] setFloat:volume forKey:@"playerVolume"];
    
    if(remotePlayer)
        [remotePlayer setVolume:volume];
}

- (void)seekToTime:(NSTimeInterval)time {
    if(remotePlayer != nil) {
        CMTime timeCM = CMTimeMakeWithSeconds(time, NSEC_PER_SEC);
        [remotePlayer seekToTime:timeCM];
    }
    
    if(isCaching) {
        isCaching = NO;
    }
    
    // seeks will desync the NPIC
    [self updateSystemNowPlayingStatus];
}

// This is relative (0..100) it seems
- (void)seek:(double)time {
    if(remotePlayer != nil) {
        AVPlayerItem *currentItem = [remotePlayer currentItem];
        CMTime durationCM = [currentItem duration];
        CMTime newTime = CMTimeMultiplyByFloat64(durationCM, (time / 100.0));
        [remotePlayer seekToTime:newTime];
    }
    
    if(isCaching) {
        isCaching = NO;
    }
    
    // seeks will desync the NPIC
    [self updateSystemNowPlayingStatus];
}


- (void)relativeSeekBy: (double)increment {
    double maxTime = [self durationTime];
    double newTime = MIN(maxTime, MAX([self currentTime] + increment, 0));
    [self seekToTime: newTime];
}


- (void)rewind {
    double increment = -[[NSUserDefaults standardUserDefaults] floatForKey:@"SkipIncrement"];
    [self relativeSeekBy: increment];
}


- (void)fastForward {
    double increment = [[NSUserDefaults standardUserDefaults] floatForKey:@"SkipIncrement"];
    [self relativeSeekBy: increment];
}


- (void)stop {

    @synchronized(self) {
        // stop players
        if(remotePlayer) {
            [remotePlayer replaceCurrentItemWithPlayerItem:nil];
        }
        
        // unplay current track
        [self.currentTrack setIsPlaying:[NSNumber numberWithBool:NO]];
        self.currentTrack  = nil;
        
        // unplay all
        [self unplayAllTracks];
        
        // stop player !
        self.isPlaying = NO;
        self.isPaused = YES; // for sure
        
        // update NPIC
        [self updateSystemNowPlaying];
        [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlayStateNotification object:self];
        [[NSNotificationCenter defaultCenter] postNotificationName:SBPlayerPlaylistUpdatedNotification object:self];
	}
}


- (void)clear {
    //[self stop];
    [self.playlist removeAllObjects];
    [self setCurrentTrack:nil];
}


#pragma mark -
#pragma mark Accessors (Player Properties)

/**
  Intended for player subtitles (i.e. NSWindow, notifications
 */
- (NSString*)subtitle {
    if ([self.currentTrack isKindOfClass: SBEpisode.class]) {
        SBEpisode *currentEpisode = (SBEpisode*)self.currentTrack;
        return currentEpisode.podcast.itemName ?: (currentTrack.artistName ?: currentTrack.artistString);
    }
    return [NSString stringWithFormat: @"%@ — %@", currentTrack.artistName ?: currentTrack.artistString, currentTrack.albumString];
}


- (NSTimeInterval)currentTime {
    
    if(remotePlayer != nil)
    {
        CMTime currentTimeCM = [remotePlayer currentTime];
        NSTimeInterval currentTime = CMTimeGetSeconds(currentTimeCM);
        return currentTime;
    }
    
    return 0;
}


- (NSString *)currentTimeString {
    return [NSString stringWithTime: [self currentTime]];
}

- (NSTimeInterval)durationTime
{
    if(remotePlayer != nil)
    {
        AVPlayerItem *currentItem = [remotePlayer currentItem];
        CMTime durationCM = [currentItem duration];
        NSTimeInterval duration = CMTimeGetSeconds(durationCM);
        return duration;
    }
    
    return 0;
}

- (NSTimeInterval)remainingTime
{
    if(remotePlayer != nil)
    {
        AVPlayerItem *currentItem = [remotePlayer currentItem];
        CMTime durationCM = [currentItem duration];
        CMTime currentTimeCM = [currentItem currentTime];
        NSTimeInterval duration = CMTimeGetSeconds(durationCM);
        NSTimeInterval currentTime = CMTimeGetSeconds(currentTimeCM);
        NSTimeInterval remainingTime = duration-currentTime;
        return remainingTime;
    }
    
    return 0;
}

- (NSString *)remainingTimeString {
    return [NSString stringWithTime: [self remainingTime]];
}

- (double)progress {
    if(remotePlayer != nil)
    {
        // typedef struct { long long timeValue; long timeScale; long flags; } QTTime
        AVPlayerItem *currentItem = [remotePlayer currentItem];
        CMTime durationCM = [currentItem duration];
        CMTime currentTimeCM = [currentItem currentTime];
        NSTimeInterval duration = CMTimeGetSeconds(durationCM);
        NSTimeInterval currentTime = CMTimeGetSeconds(currentTimeCM);
        
        if(duration > 0) {
            double progress = ((double)currentTime) / ((double)duration) * 100; // make percent
            //double bitrate = [[[remotePlayer movieAttributes] valueForKey:QTMovieDataSizeAttribute] doubleValue]/duration * 10;
            //NSLog(@"bitrate : %f", bitrate);
            
            if(progress == 100) { // movie is at end
                // let item finished playing handle this guy
                //[self next];
            }
            
            return progress;
            
        } else {
            return 0;
        }
    }
    
    return 0;
}


- (float)volume {
    return [[NSUserDefaults standardUserDefaults] floatForKey:@"playerVolume"];
}

- (double)percentLoaded {
    double percentLoaded = 0;

    if(remotePlayer != nil) {
        AVPlayerItem *currentItem = [remotePlayer currentItem];
        CMTime durationCM = [currentItem duration];
        NSTimeInterval tMaxLoaded;
        NSArray *ranges = [currentItem loadedTimeRanges];
        if ([ranges count] > 0) {
            CMTimeRange range = [[ranges firstObject] CMTimeRangeValue];
            tMaxLoaded = CMTimeGetSeconds(range.duration) - CMTimeGetSeconds(range.start);
        } else {
            tMaxLoaded = 0;
        }
        NSTimeInterval tDuration = CMTimeGetSeconds(durationCM);
        
        percentLoaded = (double) tMaxLoaded/tDuration;
    }
    
    return percentLoaded;
}


- (SBPlayerRepeatMode)repeatMode {
    return (SBPlayerRepeatMode)[[NSUserDefaults standardUserDefaults] integerForKey:@"repeatMode"];
}

- (void)setRepeatMode:(SBPlayerRepeatMode)newRepeatMode {
    [[NSUserDefaults standardUserDefaults] setInteger:newRepeatMode forKey:@"repeatMode"];
    repeatMode = newRepeatMode;
}


- (BOOL)isShuffle {
    return (BOOL)[[NSUserDefaults standardUserDefaults] integerForKey:@"shuffle"];
}

// XXX: clumsy name, change in the
- (void)setIsShuffle:(BOOL)newShuffle {
    [[NSUserDefaults standardUserDefaults] setInteger:newShuffle forKey:@"shuffle"];
    isShuffle = newShuffle;
}




#pragma mark -
#pragma mark Remote Player Notification

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == remotePlayer && [keyPath isEqualToString:@"status"]) {
        if ([remotePlayer status] == AVPlayerStatusFailed) {
            NSLog(@"AVPlayer Failed: %@", [remotePlayer error]);
            [self stop];
        } else if ([remotePlayer status] == AVPlayerStatusReadyToPlay) {
            NSLog(@"AVPlayerStatusReadyToPlay");
            [remotePlayer play];
        } else if ([remotePlayer status] == AVPlayerItemStatusUnknown) {
            NSLog(@"AVPlayer Unknown");
            [self stop];
        }
    }
    
    if (object == remotePlayer && [keyPath isEqualToString: @"currentItem"]
        && [[NSUserDefaults standardUserDefaults] boolForKey:@"enableCacheStreaming"] == YES)
    {
        // Check if we've already downloaded this track.
        if (self.currentTrack != nil
            && (self.currentTrack.localTrack != nil || self.currentTrack.isLocalValue == YES)) {
            return;
        }
        
        SBSubsonicDownloadOperation *op = [[SBSubsonicDownloadOperation alloc]
                                           initWithManagedObjectContext: [self.currentTrack managedObjectContext]
                                           trackID: [self.currentTrack objectID]];
        
        [[NSOperationQueue sharedDownloadQueue] addOperation:op];
    }
}

-(void)itemDidFinishPlaying:(NSNotification *) notification {
    [self next];
}

#pragma mark -
#pragma mark Private


- (SBTrack *)getRandomTrackExceptingTrack:(SBTrack *)_track {
	
	SBTrack *randomTrack = _track;
	NSArray *sortedTracks = [self playlist];
	
	if([sortedTracks count] > 1) {
		while ([randomTrack isEqualTo:_track]) {
			NSInteger numberOfTracks = [sortedTracks count];
			NSInteger randomIndex = random() % numberOfTracks;
			randomTrack = [sortedTracks objectAtIndex:randomIndex];
		}
	} else {
		randomTrack = nil;
	}
	
	return randomTrack;
}


- (SBTrack *)nextTrack {
    
    if(self.playlist) {
        if(!isShuffle) {
            NSInteger index = [self.playlist indexOfObject:self.currentTrack];
            
            if(repeatMode == SBPlayerRepeatNo) {
                
                // no repeat, play next
                if(index > -1 && [self.playlist count]-1 >= index+1) {
                    return [self.playlist objectAtIndex:index+1];
                }
            }
                
            // if repeat one, esay to relaunch the track
            if(repeatMode == SBPlayerRepeatOne)
                return self.currentTrack;
            
            // if repeat all
            if(repeatMode == SBPlayerRepeatAll) {
                if([self.currentTrack isEqualTo:[self.playlist lastObject]] && index > 0) {
                     return [self.playlist objectAtIndex:0];
                } else {
					if(index > -1 && [self.playlist count]-1 >= index+1) {
						return [self.playlist objectAtIndex:index+1];
					}
                }
            }
            
        } else {
            // if repeat one, get the piority
            if(repeatMode == SBPlayerRepeatOne)
                return self.currentTrack;
            
            // else play random
            return [self getRandomTrackExceptingTrack:self.currentTrack];
        }
    }
    return nil;
}


- (SBTrack *)prevTrack {
    if(self.playlist) {
        if(!isShuffle) {
            NSInteger index = [self.playlist indexOfObject:self.currentTrack];   
            
            if(repeatMode == SBPlayerRepeatOne)
                return self.currentTrack;
            
            if(index == 0) {
                if(repeatMode == SBPlayerRepeatAll) {
                    return [self.playlist lastObject];
                } else {
                    // objectAtIndex for 0 - 1 is gonna throw, so don't
                    return nil;
                }
            }
            if(index != -1) {
                return [self.playlist objectAtIndex:index-1];
            }
        } else {
            // if repeat one, get the piority
            if(repeatMode == SBPlayerRepeatOne)

                return self.currentTrack;
            
            return [self getRandomTrackExceptingTrack:self.currentTrack];
        }
    }
    return nil;
}

- (void)unplayAllTracks {

    NSError *error = nil;
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"(isPlaying == YES)"];
    NSArray *tracks = [[self.currentTrack managedObjectContext] fetchEntitiesNammed:@"Track" withPredicate:predicate error:&error];
    
    for(SBTrack *track in tracks) {
        [track setIsPlaying:[NSNumber numberWithBool:NO]];
    }
}


- (void)showVideoAlert {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle: NSAlertStyleInformational];
    [alert setInformativeText: @"Submariner doesn't support video."];
    [alert setMessageText: @"No Video"];
    [alert addButtonWithTitle: @"OK"];
    [alert runModal];
}



@end
