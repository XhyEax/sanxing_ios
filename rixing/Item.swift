//
//  Item.swift
//  rixing
//
//  Created by xhy on 2026/6/20.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
