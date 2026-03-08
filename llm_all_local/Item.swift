//
//  Item.swift
//  llm_all_local
//
//  Created by 朱运鹏 on 2026/3/8.
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
