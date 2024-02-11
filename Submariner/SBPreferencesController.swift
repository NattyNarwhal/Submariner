//
//  SBPreferencesController.swift
//  Submariner
//
//  Created by Calvin Buckley on 2024-02-10.
//
//  Copyright (c) 2024 Calvin Buckley
//  SPDX-License-Identifier: BSD-3-Clause
//  

import Cocoa
import SwiftUI

// TODO: break into own file or subsume into window controller
class SBTabViewController: NSTabViewController {
    func newFrame(window: NSWindow, view: NSView) -> NSRect {
        let viewFrame = NSRect(origin: .zero, size: view.fittingSize)
        let newFrame = window.frameRect(forContentRect: viewFrame)
        let oldFrame = window.frame
        var calculatedFrame = window.frame
        // instead of size, keeps everything at a consistent width so it doesn't twitch around
        calculatedFrame.size.height = newFrame.size.height
        calculatedFrame.origin.y -= (newFrame.size.height - oldFrame.size.height)
        return calculatedFrame
    }
    
    override func viewDidAppear() {
        guard let newView = self.tabViewItems[self.selectedTabViewItemIndex].view,
              let window = self.view.window else {
            return
        }
        let newFrame = newFrame(window: window, view: newView)
        window.setFrame(newFrame, display: false)
        window.center()
    }
    
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            
            guard let newView = tabViewItem?.view,
                  let window = self.view.window else {
                return
            }
            
            let newFrame = newFrame(window: window, view: newView)
            window.animator().setFrame(newFrame, display: true)
        }
    }
}

// When we switch to the SwiftUI app lifecycle, we can just use the Settings view type.
class SBPreferencesController: NSWindowController {
    init() {
        let playerSettingsView = NSHostingController(rootView: PlayerView())
        playerSettingsView.title = "Player"
        let serverSettingsView = NSHostingController(rootView: SubsonicView())
        serverSettingsView.title = "Server"
        let appearanceSettingsView = NSHostingController(rootView: AppearanceView())
        appearanceSettingsView.title = "Appearance"
        
        let playerTab = NSTabViewItem(viewController: playerSettingsView)
        playerTab.label = playerSettingsView.title!
        playerTab.image = NSImage(systemSymbolName: "hifispeaker", accessibilityDescription: "Player Settings")
        let serverTab = NSTabViewItem(viewController: serverSettingsView)
        serverTab.label = serverSettingsView.title!
        serverTab.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Server Settings")
        let appearanceTab = NSTabViewItem(viewController: appearanceSettingsView)
        appearanceTab.label = appearanceSettingsView.title!
        appearanceTab.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Appearance Settings")
        
        let tabViewController = SBTabViewController()
        tabViewController.tabStyle = .toolbar
        tabViewController.transitionOptions = [.allowUserInteraction]
        tabViewController.tabViewItems = [playerTab, serverTab, appearanceTab]
        
        let window = NSWindow(contentViewController: tabViewController)
        window.styleMask = [.closable, .miniaturizable, .titled]
        window.title = tabViewController.tabViewItems[tabViewController.selectedTabViewItemIndex].label
        window.toolbarStyle = .preference
        
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    // #MARK: -
    // #MARK: SwiftUI Views

    struct PlayerView: View {
        @AppStorage("enableCacheStreaming") var automaticallyDownload = false
        @AppStorage("deleteAfterPlay") var deleteOnEnd = false
        @AppStorage("SkipIncrement") var skipBySeconds = 5.0
        @AppStorage("playerBehavior") var whenQueueing = 0

        var body: some View {
            Form {
                Section {
                    Toggle("Automatically download playing track", isOn: $automaticallyDownload)
                    Toggle("Delete from tracklist at track end", isOn: $deleteOnEnd)
                }
                Section {
                    Picker(selection: $whenQueueing, label: Text("When queueing a track")) {
                        Text("Append to tracklist").tag(0)
                        Text("Replace tracklist").tag(1)
                    }
                }
                Section {
                    TextField("Skip by number of seconds", value: $skipBySeconds, formatter: NumberFormatter())
                }
            }
            .fixedSize()
            // seems to be about what system apps use for padding value
            .padding(14)
            // formStyle(.grouped) is tempting, but it's not really macOS HIG for app settings (yet?)
        }
    }

    struct SubsonicView: View {
        @AppStorage("scrobbleToServer") var scrobble = false
        @AppStorage("autoRefreshNowPlaying") var autoRefreshNowPlaying = false
        @AppStorage("MaxCoverSize") var coverSize = 300

        var body: some View {
            Form {
                Section {
                    Toggle("Automatically refresh server users view", isOn: $autoRefreshNowPlaying)
                }
                Section {
                    Picker(selection: $coverSize, label: Text("Cover size to download")) {
                        Text("130x130").tag(130)
                        Text("300x300").tag(300)
                        Text("600x600").tag(600)
                    }
                }
                Section {
                    Toggle("Scrobble tracks to server", isOn: $scrobble)
                }
            }
            .fixedSize()
            .padding(14)
        }
    }
    
    struct AppearanceView: View {
        @AppStorage("coverSize") var coverSize = 0.75

        var body: some View {
            Form {
                Section {
                    Slider(value: $coverSize, in: 0...1, step: 0.05) {
                        Text("Cover size")
                    } minimumValueLabel: {
                        Text("Min")
                    } maximumValueLabel: {
                        Text("Max")
                    }
                    // the default minimum intrinsic width for a slider is paltry
                    .frame(minWidth: 250)
                }
            }
            .fixedSize()
            .padding(14)
        }
    }
}
