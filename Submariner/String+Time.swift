//
//  NSString+Time.swift
//  Submariner
//
//  Created by Calvin Buckley on 2023-02-07.
//  Copyright © 2023 Calvin Buckley. All rights reserved.
//

import Cocoa

// Remove when Objective-C version of parsing op is gone
extension String {
    fileprivate static let iso8601Formatter = ISO8601DateFormatter()
    fileprivate static let rfc3339DateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    fileprivate static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE', 'dd' 'MMM' 'yyyy' 'hh:mm:ss' GMT'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    static let componentFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
    
    func dateTimeFromISO() -> Date? {
        return String.iso8601Formatter.date(from: self as String)
    }
    
    func dateTimeFromRFC3339() -> Date? {
        return String.rfc3339DateFormatter.date(from: self as String)
    }
    
    func dateTimeFromHTTP() -> Date? {
        return String.httpDateFormatter.date(from: self)
    }

    init(timeInterval: TimeInterval) {
        if timeInterval == 0 || timeInterval.isNaN {
            self = "00:00"
            return
        }

        let ti = Int(timeInterval)
        let seconds = ti % 60
        let minutes = (ti / 60) % 60
        let hours = (ti / 3600)
        
        if (hours > 0) {
            self = String(format: "%0.2d:%0.2d:%0.2d", hours, minutes, seconds);
        }
        else {
            self = String(format: "%0.2d:%0.2d", minutes, seconds);
        }
    }
}
