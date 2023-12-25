//
//  SBServerController.m
//  Submariner
//
//  Created by Rafaël Warnault on 06/06/11.
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

#import "SBServerLibraryController.h"
#import "SBDatabaseController.h"
#import "SBAddServerPlaylistController.h"
#import "SBTableView.h"

#import "Submariner-Swift.h"




@interface SBServerLibraryController ()
- (void)subsonicCoversUpdatedNotification:(NSNotification *)notification;
- (void)subsonicTracksUpdatedNotification:(NSNotification *)notification;
@end





@implementation SBServerLibraryController



+ (NSString *)nibName {
    return @"ServerLibrary";
}


- (NSString*)title {
    return [NSString stringWithFormat: @"Artists on %@", self.server.resourceName];
}


@synthesize databaseController;
@synthesize artistSortDescriptor;
@synthesize trackSortDescriptor;

@dynamic artistCellSelectedAttributes;
@dynamic artistCellUnselectedAttributes;



- (id)initWithManagedObjectContext:(NSManagedObjectContext *)context {
    self = [super initWithManagedObjectContext:context];
    if (self) {
        groupEntity = [NSEntityDescription entityForName: @"Group" inManagedObjectContext: managedObjectContext];
        
        NSSortDescriptor *artistDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"itemName" ascending:YES];
        artistSortDescriptor = [NSArray arrayWithObject:artistDescriptor];
        
        // XXX: Useful to change by i.e. year instead or alphabetical, but that's not a property of Album
        NSSortDescriptor *albumDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"itemName" ascending:YES];
        albumSortDescriptor = @[albumDescriptor];
        
        NSSortDescriptor *trackNumberDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"trackNumber" ascending:YES];
        NSSortDescriptor *discNumberDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"discNumber" ascending:YES];
        trackSortDescriptor = @[discNumberDescriptor, trackNumberDescriptor];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    
    // set initial filter, we can perhaps persist between launches by storing in the text for filter
    [self filterArtist: filterView];
    
    self->compensatedSplitView = self->rightSplitView;
    // so it doesn't resize unless the user does so
    artistSplitView.delegate = self;
}

- (void)viewDidAppear {
    [super viewDidAppear];
    // XXX: see -[SBMusicController viewDidAppear]
    [albumsBrowserView setZoomValue:[[NSUserDefaults standardUserDefaults] floatForKey:@"coverSize"]];
    [[NSNotificationCenter defaultCenter] postNotificationName: @"SBTrackSelectionChanged"
                                                        object: tracksController.selectedObjects];
}

- (void)dealloc
{
    // remove subsonic observers
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"SBSubsonicCoversUpdatedNotification" object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"SBSubsonicTracksUpdatedNotification" object:nil];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:@"coverSize"];
    [albumsController removeObserver:self forKeyPath:@"selectedObjects"];
    [tracksController removeObserver:self forKeyPath:@"selectedObjects"];
}

- (void)loadView {
    [super loadView];
    
    [tracksTableView registerForDraggedTypes:[NSArray arrayWithObject:SBLibraryTableViewDataType]];
    [tracksTableView setTarget:self];
    [tracksTableView setDoubleAction:@selector(trackDoubleClick:)];

    [albumsBrowserView setZoomValue:[[NSUserDefaults standardUserDefaults] floatForKey:@"coverSize"]];
    
    // observer browser zoom value
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:@"coverSize" 
                                               options:NSKeyValueObservingOptionNew
                                               context:nil];
    
    // observe album covers
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(subsonicCoversUpdatedNotification:) 
                                                 name:@"SBSubsonicCoversUpdatedNotification"
                                               object:nil];
    
    // observe tracks
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(subsonicTracksUpdatedNotification:) 
                                                 name:@"SBSubsonicTracksUpdatedNotification"
                                               object:nil];
    
    // Observe album for saving. Artist isn't observed because it triggers after for some reason.
    [albumsController addObserver:self
                      forKeyPath:@"selectedObjects"
                      options:NSKeyValueObservingOptionNew
                      context:nil];
    
    [tracksController addObserver:self
                      forKeyPath:@"selectedObjects"
                      options:NSKeyValueObservingOptionNew
                      context:nil];
}


- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object 
                        change:(NSDictionary *)change 
                       context:(void *)context {
    
    if(object == [NSUserDefaults standardUserDefaults] && [keyPath isEqualToString:@"coverSize"]) {
        [albumsBrowserView setZoomValue:[[NSUserDefaults standardUserDefaults] floatForKey:@"coverSize"]];
        [albumsBrowserView setNeedsDisplay:YES];
    } else if (object == albumsController && [keyPath isEqualToString:@"selectedObjects"]) {
        SBAlbum *album = albumsController.selectedObjects.firstObject;
        if (album != nil) {
            NSString *urlString = album.objectID.URIRepresentation.absoluteString;
            [[NSUserDefaults standardUserDefaults] setObject: urlString forKey: @"LastViewedResource"];
        }
    } else if (object == tracksController && [keyPath isEqualToString:@"selectedObjects"] && self.view.window != nil) {
        [[NSNotificationCenter defaultCenter] postNotificationName: @"SBTrackSelectionChanged"
                                                            object: tracksController.selectedObjects];
    }
}

- (NSDictionary *)artistCellSelectedAttributes {
    if(artistCellSelectedAttributes == nil) {
        artistCellSelectedAttributes = [NSMutableDictionary dictionary];
        
        return artistCellSelectedAttributes;
    }
    return artistCellSelectedAttributes;
}

- (NSDictionary *)artistCellUnselectedAttributes {
    if(artistCellUnselectedAttributes == nil) {
        artistCellUnselectedAttributes = [NSMutableDictionary dictionary];
        
        return artistCellUnselectedAttributes;
    }
    return artistCellUnselectedAttributes;
}


/// Gets the selected track, album, or artist, in that order. Used mostly for saving state.
- (SBMusicItem*) selectedItem {
    NSInteger selectedTracks = [tracksTableView selectedRow];
    if (selectedTracks != -1) {
        return [tracksController.arrangedObjects objectAtIndex: selectedTracks];
    }
    NSIndexSet *selectedAlbums = [albumsBrowserView selectionIndexes];
    if ([selectedAlbums count] > 0) {
        return [albumsController.arrangedObjects objectAtIndex: [selectedAlbums firstIndex]];
    }
    NSInteger selectedArtists = [artistsTableView selectedRow];
    if (selectedArtists != -1) {
        return [artistsController.arrangedObjects objectAtIndex: selectedArtists];
    }
    return nil;
}


#pragma mark - 
#pragma mark Notification

- (void)subsonicCoversUpdatedNotification:(NSNotification *)notification {
    [albumsBrowserView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
}

- (void)subsonicTracksUpdatedNotification:(NSNotification *)notification {
    [tracksTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
}


#pragma mark - 
#pragma mark IBActions

- (IBAction)addArtistToTracklist:(id)sender {
    NSInteger selectedRow = [artistsTableView selectedRow];
    
    if(selectedRow != -1) {
        SBArtist *artist = [[artistsController arrangedObjects] objectAtIndex:selectedRow];
        NSMutableArray *tracks = [NSMutableArray array];
        
        for(SBAlbum *album in artist.albums) {
            [tracks addObjectsFromArray:[album.tracks sortedArrayUsingDescriptors:trackSortDescriptor]];
        }
        
        [[SBPlayer sharedInstance] addTrackArray:tracks replace:NO];
    }
}


- (IBAction)addAlbumToTracklist:(id)sender {
    NSIndexSet *indexSet = [albumsBrowserView selectionIndexes];
    NSInteger selectedRow = [indexSet firstIndex];
    
    if(selectedRow != -1) {
        SBAlbum *album = [[albumsController arrangedObjects] objectAtIndex:selectedRow];
        [[SBPlayer sharedInstance] addTrackArray:[album.tracks sortedArrayUsingDescriptors:trackSortDescriptor] replace:NO];
    }
}


- (IBAction)addTrackToTracklist:(id)sender {
    NSIndexSet *indexSet = [tracksTableView selectedRowIndexes];
    NSMutableArray *tracks = [NSMutableArray array];
    
    [indexSet enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [tracks addObject:[[tracksController arrangedObjects] objectAtIndex:idx]];
    }];
    
    [[SBPlayer sharedInstance] addTrackArray:tracks replace:NO];
}


- (IBAction)addSelectedToTracklist:(id)sender {
    NSResponder *responder = self.databaseController.window.firstResponder;
    if (responder == tracksTableView) {
        [self addTrackToTracklist: self];
    } else if (responder == albumsBrowserView) {
        [self addAlbumToTracklist: self];
    } else if (responder == artistsTableView) {
        [self addArtistToTracklist: self];
    }
}


- (IBAction)createNewLocalPlaylistWithSelectedTracks:(id)sender {
    NSInteger selectedRow = [tracksTableView selectedRow];
    
    if(selectedRow == -1) {
        return;
    }
    
    [self createLocalPlaylistWithSelected: tracksController.arrangedObjects selectedIndices: tracksTableView.selectedRowIndexes databaseController: self.databaseController];
}


- (IBAction)createNewPlaylistWithSelectedTracks:(id)sender {
    // get selected rows track objects
    NSIndexSet *rowIndexes = [tracksTableView selectedRowIndexes];
    NSMutableArray *tracks = [NSMutableArray array];
    
    // create an IDs array
    [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [tracks addObject:[[tracksController arrangedObjects] objectAtIndex:idx]];
    }];
    
    [databaseController.addServerPlaylistController setServer:self.server];
    [databaseController.addServerPlaylistController setTracks:tracks];
    [databaseController.addServerPlaylistController openSheet:sender];
}


- (IBAction)filterArtist:(id)sender {
    
    NSPredicate *predicate = nil;
    NSString *searchString = nil;
    
    searchString = [sender stringValue];
    
    // Including server is redundant, since the artistController dervives from server's own indexSet
    // Filter out nil ids to avoid confusing user, since only thing that can make those is i.e. playlist from index-based IDs
    // If we don't include group, we won't have the headers
    if(searchString != nil && [searchString length] > 0) {
        // We don't need to worry about filtering group names here.
        // If we do want groups, then we should reverse the search if it's a group (%@ begins with itemName)
        predicate = [NSPredicate predicateWithFormat:@"(itemName CONTAINS[cd] %@ && itemId != nil)", searchString];
        [artistsController setFilterPredicate:predicate];
    } else {
        predicate = [NSPredicate predicateWithFormat:@"(itemId != nil || entity == %@)", groupEntity];
        [artistsController setFilterPredicate:predicate];
    }
}

- (IBAction)trackDoubleClick:(id)sender {
    NSInteger selectedRow = [tracksTableView selectedRow];
    if(selectedRow != -1) {
        [[SBPlayer sharedInstance] playTracks: [tracksController arrangedObjects] startingAt: selectedRow];
    }
}

- (IBAction)albumDoubleClick:(id)sender {
    NSIndexSet *indexSet = [albumsBrowserView selectionIndexes];
    NSInteger selectedRow = [indexSet firstIndex];
    if(selectedRow != -1) {
        SBAlbum *doubleClickedAlbum = [[albumsController arrangedObjects] objectAtIndex:selectedRow];
        if(doubleClickedAlbum) {
            
            NSArray *tracks = [doubleClickedAlbum.tracks sortedArrayUsingDescriptors:trackSortDescriptor];
            [[SBPlayer sharedInstance] playTracks: tracks startingAt: 0];
        }
    }
}


- (IBAction)playSelected:(id)sender {
    NSResponder *responder = self.databaseController.window.firstResponder;
    if (responder == tracksTableView) {
        [self trackDoubleClick: self];
    } else if (responder == albumsBrowserView) {
        [self albumDoubleClick: self];
    }
}


- (IBAction)showSelectedInFinder:(id)sender {
    NSInteger selectedRow = [tracksTableView selectedRow];
    
    if(selectedRow == -1) {
        return;
    }
    
    [self showTracksInFinder: tracksController.arrangedObjects selectedIndices: tracksTableView.selectedRowIndexes];
}


- (IBAction)downloadTrack:(id)sender {
    NSInteger selectedRow = [tracksTableView selectedRow];
    
    if(selectedRow != -1) {
        [self downloadTracks: tracksController.arrangedObjects selectedIndices: tracksTableView.selectedRowIndexes databaseController: databaseController];
    }
}

 
- (IBAction)downloadAlbum:(id)sender{
    NSIndexSet *indexSet = [albumsBrowserView selectionIndexes];
    NSInteger selectedRow = [indexSet firstIndex];
    if(selectedRow != -1) {
        SBAlbum *doubleClickedAlbum = [[albumsController arrangedObjects] objectAtIndex:selectedRow];
        if(doubleClickedAlbum) {
            
            [databaseController showDownloadView: self];
			
            NSArray *tracks = [doubleClickedAlbum.tracks sortedArrayUsingDescriptors:trackSortDescriptor];
            
            for(SBTrack *track in tracks) {
                SBSubsonicDownloadOperation *op = [[SBSubsonicDownloadOperation alloc]
                                                   initWithManagedObjectContext: self.managedObjectContext
                                                   trackID: [track objectID]];
                
                [[NSOperationQueue sharedDownloadQueue] addOperation:op];
            }
        }
    }
}


- (IBAction)downloadSelected:(id)sender {
    NSResponder *responder = self.databaseController.window.firstResponder;
    if (responder == tracksTableView) {
        [self downloadTrack: self];
    } else if (responder == albumsBrowserView) {
        [self downloadAlbum: self];
    }
}


- (void)showTrackInLibrary:(SBTrack*)track {
    [artistsController setSelectedObjects: @[track.album.artist]];
    [artistsTableView scrollRowToVisible: [artistsTableView selectedRow]];
    [albumsController setSelectedObjects: @[track.album]];
    [artistsTableView scrollRowToVisible: [artistsTableView selectedRow]];
    [tracksController setSelectedObjects: @[track]];
    [tracksTableView scrollRowToVisible: [tracksTableView selectedRow]];
}


- (void)showAlbumInLibrary:(SBAlbum*)album {
    [artistsController setSelectedObjects: @[album.artist]];
    [artistsTableView scrollRowToVisible: [artistsTableView selectedRow]];
    [albumsController setSelectedObjects: @[album]];
    [artistsTableView scrollRowToVisible: [artistsTableView selectedRow]];
}


- (void)showArtistInLibrary:(SBArtist*)artist {
    [artistsController setSelectedObjects: @[artist]];
    [artistsTableView scrollRowToVisible: [artistsTableView selectedRow]];
}






#pragma mark -
#pragma mark NoodleTableView Delegate (Artist Indexes)

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    BOOL ret = NO;
    
    if(tableView == artistsTableView) {
        if(row > -1) {
            SBGroup *group = [[artistsController arrangedObjects] objectAtIndex:row];
            if(group && [group isKindOfClass:[SBGroup class]])
                ret = YES;
        }
    }
	return ret;
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    BOOL ret = YES;
    
    if(tableView == artistsTableView) {
        if(row > -1) {
            SBGroup *group = [[artistsController arrangedObjects] objectAtIndex:row];
            if(group && [group isKindOfClass:[SBGroup class]])
                ret = NO;
        }
    }
	return ret;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    
    if(tableView == artistsTableView) {
        if(row != -1) {
            SBIndex *index = [[artistsController arrangedObjects] objectAtIndex:row];
            if(index && [index isKindOfClass:[SBArtist class]])
                return 22.0f;
            else if(index && [index isKindOfClass:[SBGroup class]])
                return 20.0f;
        }
    }
    return 17.0f;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    
    if([notification object] == artistsTableView) {
        NSInteger selectedRow = [[notification object] selectedRow];
        if(selectedRow != -1) {
            SBArtist *selectedArtist = [[artistsController arrangedObjects] objectAtIndex:selectedRow];
            if(selectedArtist && [selectedArtist isKindOfClass:[SBArtist class]]) {
                [self.server getArtist:selectedArtist];
                [albumsBrowserView setSelectionIndexes:nil byExtendingSelection:NO];
            }
        }
    }
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if(tableView == artistsTableView) {
        if(row > -1) {
            SBIndex *index = [[artistsController arrangedObjects] objectAtIndex:row];
            if(index && [index isKindOfClass:[SBArtist class]]) {

                NSDictionary *attr = (row == [tableView selectedRow]) ? self.artistCellSelectedAttributes : self.artistCellUnselectedAttributes;
                NSString *str = index.itemName ?: @"";
                NSAttributedString *newString = [[NSAttributedString alloc] initWithString: str attributes:attr];
                
                [cell setAttributedStringValue:newString];
            }
        }
    }
}


#pragma mark - NSTableView (Columns)


- (BOOL)tableView:(NSTableView *)tableView userCanChangeVisibilityOfTableColumn:(NSTableColumn *)column {
    return YES;
}


#pragma mark -
#pragma mark NSTableView (Drag & Drop)

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard {
    
    BOOL ret = NO;
    if(tableView == tracksTableView) {
        /*** Internal drop track */
        NSMutableArray *trackURIs = [NSMutableArray array];
        
        // get tracks URIs
        [rowIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
            SBTrack *track = [[tracksController arrangedObjects] objectAtIndex:idx];
            [trackURIs addObject:[[track objectID] URIRepresentation]];
        }];
        
        // encode to data
        NSError *error = nil;
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:trackURIs requiringSecureCoding: YES error: &error];
        if (error != nil) {
            NSLog(@"Error archiving track URIs: %@", error);
            return NO;
        }
        
        // register data to pastboard
        [pboard declareTypes:[NSArray arrayWithObject:SBLibraryTableViewDataType] owner:self];
        [pboard setData:data forType:SBLibraryTableViewDataType];
        ret = YES;
    }
    return ret;
}



#pragma mark -
#pragma mark Tracks NSTableView DataSource (Rating)

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
    if(aTableView == tracksTableView) {
        if([[aTableColumn identifier] isEqualToString:@"rating"]) {
            
            NSInteger selectedRow = [tracksTableView selectedRow];
            if(selectedRow != -1) {
                SBTrack *clickedTrack = [[tracksController arrangedObjects] objectAtIndex:selectedRow];
                
                if(clickedTrack) {
                    
                    NSInteger rating = [anObject intValue];
                    NSString *trackID = [clickedTrack itemId];
                    
                    [self.server setRating:rating forID:trackID];
                }
            }
        }
    }
}


#pragma mark -
#pragma mark NSTableView Sort Descriptor Override


- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    if (tableView == tracksTableView && tableColumn == tableView.tableColumns[0]) {
        // Make sure we're using the sort order for disc then track for track column
        // We have to build a new array because NSTableView appends.
        BOOL asc = (tracksController.sortDescriptors[0].ascending);
        NSSortDescriptor *trackNumberDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"trackNumber" ascending: !asc];
        NSSortDescriptor *discNumberDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"discNumber" ascending: !asc];
        tracksController.sortDescriptors = @[discNumberDescriptor, trackNumberDescriptor];
    }
}


#pragma mark -
#pragma mark IKImageBrowserViewDelegate

- (void)imageBrowserSelectionDidChange:(IKImageBrowserView *)aBrowser {
    
    // get tracks
    NSInteger selectedRow = [[aBrowser selectionIndexes] firstIndex];
    if(selectedRow != -1 && selectedRow < [[albumsController arrangedObjects] count]) {
        
        [tracksController setContent:nil];
        
        SBAlbum *album = [[albumsController arrangedObjects] objectAtIndex:selectedRow];
        if(album) {
            
            [self.server getAlbum: album];
            
            if([album.tracks count] == 0) {                
                // wait for new tracks
//                [album addObserver:self
//                        forKeyPath:@"tracks"
//                           options:(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
//                           context:NULL];

            } else {
                [tracksController setContent:album.tracks];
            }
        } else {
            [tracksController setContent:nil];
        }
    } else {
        [tracksController setContent:nil];
    }
}

- (void)imageBrowser:(IKImageBrowserView *)aBrowser cellWasDoubleClickedAtIndex:(NSUInteger)index {
    [self albumDoubleClick:nil];
}


#pragma mark -
#pragma mark NSSplitViewDelegate

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view {
    if (splitView == artistSplitView) {
        return view != splitView.subviews.firstObject;
    }
    return YES;
}


#pragma mark -
#pragma mark UI Validator

- (BOOL)validateUserInterfaceItem: (id<NSValidatedUserInterfaceItem>) item {
    SEL action = [item action];
    
    NSInteger artistsSelected = artistsTableView.selectedRowIndexes.count;
    NSInteger albumSelected = albumsBrowserView.selectionIndexes.count;
    NSInteger tracksSelected = tracksTableView.selectedRowIndexes.count;
    
    NSResponder *responder = self.databaseController.window.firstResponder;
    BOOL tracksActive = responder == tracksTableView;
    BOOL albumsActive = responder == albumsBrowserView;
    BOOL artistsActive = responder == artistsTableView;
    
    SBSelectedRowStatus selectedTrackRowStatus = 0;
    if (tracksActive) {
        selectedTrackRowStatus = [self selectedRowStatus: tracksController.arrangedObjects selectedIndices: tracksTableView.selectedRowIndexes];
    }
    
    if (action == @selector(playSelected:)) {
        return (albumSelected > 0 && albumsActive) || (tracksSelected > 0 && tracksActive);
    }
    
    if (action == @selector(addSelectedToTracklist:)) {
        return (albumSelected > 0 && albumsActive) || (tracksSelected > 0 && tracksActive) || (artistsSelected > 0 && artistsActive);
    }
    
    if (action == @selector(createNewPlaylistWithSelectedTracks:)
        || action == @selector(trackDoubleClick:)
        || action == @selector(addTrackToTracklist:)
        || action == @selector(createNewLocalPlaylistWithSelectedTracks:)) {
        return tracksSelected > 0;
    }
    
    if (action == @selector(showSelectedInFinder:)) {
        return selectedTrackRowStatus & SBSelectedRowShowableInFinder;
    }
    
    if (action == @selector(downloadTrack:)) {
        return selectedTrackRowStatus & SBSelectedRowDownloadable;
    }
    
    if (action == @selector(downloadSelected:)) {
        return (selectedTrackRowStatus & SBSelectedRowDownloadable) || (albumSelected > 0 && albumsActive);
    }
    
    // for context menus
    if (action == @selector(albumDoubleClick:)
        || action == @selector(downloadAlbum:)
        || action == @selector(addAlbumToTracklist:)) {
        return albumSelected > 0;
    }
    
    if (action == @selector(addArtistToTracklist:)) {
        return artistsSelected > 0;
    }

    return YES;
}


@end
