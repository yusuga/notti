//
//  main.swift
//  notti
//
//  Created by Yu Sugawara on 8/28/16.
//  Copyright © 2016 Yu Sugawara. All rights reserved.
//

import Foundation
import CoreBluetooth

let arguments = Process.arguments.suffixFrom(1)
let verbose = arguments.contains("-v") || arguments.contains("--verbose")

if verbose { print("arguments: \(arguments)") }

let client = BLEClient()

if !client.poweredOn() {
    print("Failed to power on. state: \(client.centralManager.state.rawValue)")
    exit(#line)
}

guard let notti = client.findNotti else {
    print("Failed to find notti.")
    exit(#line)
}

if !client.connect(notti) {
    print("Failed to connect. {\n\tnotti: \(notti)\n}")
    exit(#line)
}

defer {
    if !client.disconnect(notti) {
        print("Failed to disconnect. {\n\tnotti: \(notti)\n}")
        exit(#line)
    }
    if verbose {
        print("Success. {\n\tnotti: \(notti)\n}")
    } else {
        print("Success.")
    }
}

guard let colorService = client.discoverColorService(notti) else {
    print("Failed to discover service. {\n\tnotti: \(notti)\n}")
    exit(#line)
}

if verbose { print("Discoverd service. {\n\tcolorService: \(colorService)\n}") }

guard let reciver = client.discoverReciverCharacteristic(notti, colorService: colorService) else {
    print("Failed to discover characteristic. {\n\tnotti: \(notti)\n\tcolorService: \(colorService)\n}")
    exit(#line)
}

if verbose { print("Discoverd reciver. {\n\treciver: \(reciver)\n}") }

let data = Color(argument: arguments.first).data
if verbose { print("Will write data {\n\tdata: \(data)\n}") }

if !client.write(notti, reciver: reciver, data: data) {
    print("Failed to write data. {\n\t(\(data))\n}")
    exit(#line)
}
