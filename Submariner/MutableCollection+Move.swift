//
//  MutableCollection+Move.swift
//  Submariner
//
//  Created by Calvin Buckley on 2024-06-20.
//
//  Copyright (c) 2024 Calvin Buckley
//  SPDX-License-Identifier: BSD-3-Clause
//  

import Foundation

extension MutableCollection where Index == Int {
    mutating func moveReturningNewIndices(fromOffsets offsets: IndexSet, toOffset offset: Int) -> IndexSet {
        if #available(macOS 15, *) {
            return IndexSet(integersIn: self.moveSubranges(RangeSet(offsets), to: offset))
        }
        
        self.move(fromOffsets: offsets, toOffset: offset)
        
        var newRow = offset
        for index in offsets {
            if index < newRow {
                newRow -= 1
            }
        }
        let lastRow = newRow + offsets.count - 1
        let newRange = newRow...lastRow
        let newIndexSet = IndexSet(integersIn: newRange)
        
        return newIndexSet
    }
}
