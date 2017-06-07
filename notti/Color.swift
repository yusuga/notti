//
//  Color.swift
//  notti
//
//  Created by Yu Sugawara on 8/28/16.
//  Copyright © 2016 Yu Sugawara. All rights reserved.
//

import Foundation

internal struct Color {
    var red: UInt8 = 0x00
    var green: UInt8 = 0x00
    var blue: UInt8 = 0x00
    
    init(argument: String?) {
        guard let argument = argument else { return }
        
        var hex: UInt32 = 0
        if !Scanner(string: argument).scanHexInt32(&hex) { return }
        
        red = UInt8(hex >> 16)
        green = UInt8((hex >> 8) & 0xff)
        blue = UInt8(hex & 0xff)
    }
    
    var data: Data {
        let bytes: [UInt8] = [0x06, 0x01, red, green, blue]
        if verbose { print("Create bytes. {\n\tbytes: \(bytes)\n}") }
        return Data(bytes: UnsafePointer<UInt8>(bytes),
                      count: bytes.count)
    }
}
