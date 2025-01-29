//
//  SBPlaylistController.swift
//  Submariner
//
//  Created by Calvin Buckley on 2024-06-03.
//
//  Copyright (c) 2024 Calvin Buckley
//  SPDX-License-Identifier: BSD-3-Clause
//  

import Cocoa

@objc(SBPlaylistController) class SBPlaylistController: SBViewController, NSTableViewDelegate, NSTableViewDataSource {
    // nulled means this playlist got deleted and hopefully the UI switched away from this VC correctly
    @objc var playlist: SBPlaylist! {
        didSet {
            if let playlistName = playlist?.resourceName {
                self.title = "Playlist \"\(playlistName)\""
            } else {
                self.title = "No Playlist"
            }
        }
    }
    @objc var playlistSortDescriptors: [NSSortDescriptor] = []
    
    @IBOutlet var tracksTableView: SBTableView!
    @IBOutlet var tracksController: NSArrayController!
    
    override class func nibName() -> String! {
        "Playlist"
    }
    
    private var selectionObserver: NSKeyValueObservation?
    
    override func loadView() {
        super.loadView()
        
        tracksTableView.registerForDraggedTypes([.libraryItem, .libraryItems])
        
        selectionObserver = tracksController.observe(\.selectedObjects) { ac, value in
            if self.view.window != nil {
                NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: self.tracksController.selectedObjects)
            }
        }
    }
    
    override func viewDidAppear() {
        NotificationCenter.default.post(name: .SBTrackSelectionChanged, object: self.tracksController.selectedObjects)
    }
    
    // #MARK: - Properties
    
    override var tracks: [SBTrack]! {
        tracksController.arrangedObjects as? [SBTrack]
    }
    
    override var selectedTracks: [SBTrack]! {
        tracksController.selectedObjects as? [SBTrack]
    }
    
    override var selectedTrackRow: Int {
        tracksTableView.selectedRow
    }
    
    // #MARK: - Actions
    
    @IBAction func removeTrack(_ sender: Any) {
        if selectedTracks.count > 0 {
            let alert = NSAlert()
            let removeButton = alert.addButton(withTitle: "Remove")
            removeButton.hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            alert.messageText = "Remove the selected tracks?"
            alert.informativeText = "The selected tracks will be removed from this playlist."
            alert.alertStyle = .warning
            
            alert.beginSheetModal(for: self.view.window!) { response in
                if response != .alertFirstButtonReturn {
                    return
                }
                
                let indices = self.tracksController.selectionIndexes
                self.playlist.remove(indices: indices)
                
                // update on server all at once
                guard let server = self.playlist.server, let playlistID = self.playlist.itemId else {
                    return
                }
                let indexArray = Array(indices)
                server.updatePlaylist(ID: playlistID, removing: indexArray)
            }
        }
    }
    
    @IBAction func delete(_ sender: Any) {
        self.removeTrack(sender)
    }
    
    // SBPlaylistController doesn't inherit from SBServerViewController,
    // because it isn't inherently a server thing. This means we have to
    // implement it ourselves. Luckily, the ObjC world only cares if we
    // implement this selector, not if we inherit from the server VC.
    @IBAction func createNewPlaylistWithSelectedTracks(_ sender: Any) {
        guard let server = playlist.server else {
            return
        }
        
        databaseController.addServerPlaylistController.server = server
        databaseController.addServerPlaylistController.tracks = selectedTracks
        databaseController.addServerPlaylistController.openSheet(sender)
    }
    
    // #MARK: - NSTableView (Drag & Drop)
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        if tableView == tracksTableView {
            let track = tracks[row]
            return SBLibraryItemPasteboardWriter(item: track, index: row)
        }
        return nil
    }
    
    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard row != -1 && dropOperation == .above else {
            return []
        }
        
        if let sourceTable = info.draggingSource as? SBTableView, sourceTable == tracksTableView {
            return .move
        } else if info.draggingPasteboard.libraryItems() != nil {
            return .copy
        }
        return []
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        // XXX: For some reason, draggingSourceOperationMask has all bits set?
        if let sourceTable = info.draggingSource as? SBTableView, sourceTable == tracksTableView {
            let indices = info.draggingPasteboard.rowIndices()
            if let newIndexSet = playlist.moveTracks(fromOffsets: indices, toOffset: row) {
                tracksTableView.selectRowIndexes(newIndexSet, byExtendingSelection: false)
            }
        } else if let tracks = info.draggingPasteboard.libraryItems(managedObjectContext: self.managedObjectContext) {
            playlist.add(tracks: tracks, at: row)
        }
        
        tracksController.rearrangeObjects()
        tracksTableView.reloadData()
        
        // submit changes to server, this uses createPlaylist behind the scenes since we can reorder with it
        if let server = playlist.server, let playlistID = playlist.itemId {
            server.updatePlaylist(ID: playlistID, tracks: tracks)
        }
        return true
    }
    
    // #MARK: - NSTableView (Rating)
    
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        // previous version checked selectedRow, which seems redundant if we have row passed
        if tableView == tracksTableView && tableColumn?.identifier.rawValue == "rating" {
            let clickedTrack = tracks[row]
            
            guard let ratingNumber = object as? NSNumber else {
                return
            }
            
            clickedTrack.server?.setRating(ratingNumber.intValue, id: clickedTrack.itemId!)
        }
    }
    
    // #MARK: - UI Validator
    
    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let tracksSelected = selectedTracks.count
        
        switch item.action {
        case #selector(SBPlaylistController.createNewPlaylistWithSelectedTracks(_:)):
            return playlist.server != nil && tracksSelected > 0
        case #selector(SBPlaylistController.removeTrack(_:)),
            #selector(SBPlaylistController.delete(_:)):
            return tracksSelected > 0
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
