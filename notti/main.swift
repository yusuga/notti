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

internal class Delegator: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private static let nottiUUID = NSUUID(UUIDString: "B1C06DCE-8935-4E0D-8AED-8432F2DBC73C")
    private static let colorServiceCBUUID = CBUUID(string: "FFF0")
    private static let colorReciverCBUUID = CBUUID(string: "FFF3")
    
    private weak var centralManager: CBCentralManager!
    
    init(centralManager: CBCentralManager) {
        self.centralManager = centralManager
        super.init()
        centralManager.delegate = self
    }
    
    // MARK: -
    
    private let timeout = dispatch_time(DISPATCH_TIME_NOW, Int64(NSEC_PER_SEC*10))
    
    func poweredOn() -> Bool {
        if centralManager.state == .PoweredOn { return true }
        
        let semaphore = dispatch_semaphore_create(0)
        poweredOnHandler = { dispatch_semaphore_signal(semaphore) }
        dispatch_semaphore_wait(semaphore, timeout)
        
        return centralManager.state == .PoweredOn
    }
    private var poweredOnHandler: (() -> Void)?
    
    var findNotti: CBPeripheral? {
        if centralManager.state != .PoweredOn {
            if verbose { print("Error: centralManager is powerd off. {\n\tcentralManager: \(centralManager)\n}") }
            return nil
        }
        
        let cbUUID = Delegator.colorServiceCBUUID
        
        if let notti = centralManager?.retrieveConnectedPeripheralsWithServices([cbUUID]).first {
            if verbose { print("Retrive peripheral. {\n\tnotti: \(notti)\n}") }
            notti.delegate = self
            return notti
        }
        
        var notti: CBPeripheral?
        
        let semaphore = dispatch_semaphore_create(0)
        findNottiHandler = { [weak self] (peripheral: CBPeripheral) -> Void in
            if peripheral.identifier == Delegator.nottiUUID {
                if verbose { print("Found notti. {\n\tnotti: \(peripheral)\n}") }
                peripheral.delegate = self
                notti = peripheral
                self?.findNottiHandler = nil
                dispatch_semaphore_signal(semaphore)
            }
        }
        centralManager.scanForPeripheralsWithServices([cbUUID], options: nil)
        dispatch_semaphore_wait(semaphore, timeout)
        centralManager.stopScan()
        
        return notti
    }
    private var findNottiHandler: ((peripheral: CBPeripheral) -> Void)?
    
    func connect(peripheral: CBPeripheral) -> Bool {
        if peripheral.state == .Connected { return true }
        
        let semaphore = dispatch_semaphore_create(0)
        connectHandler = { dispatch_semaphore_signal(semaphore) }
        centralManager.connectPeripheral(peripheral, options: nil)
        dispatch_semaphore_wait(semaphore, timeout)
        
        return peripheral.state == .Connected
    }
    private var connectHandler: (() -> Void)?
    
    func discoverColorService(notti: CBPeripheral) -> CBService? {
        let cbUUID = Delegator.colorServiceCBUUID
        
        if let service = notti.services?.first where service.UUID == cbUUID { return service }
        
        let semaphore = dispatch_semaphore_create(0)
        discoverColorServiceHandler = { dispatch_semaphore_signal(semaphore) }
        notti.discoverServices([cbUUID])
        dispatch_semaphore_wait(semaphore, timeout)
        
        let service = notti.services?.first
        return service?.UUID == cbUUID ? service : nil
    }
    private var discoverColorServiceHandler: (() -> Void)?
    
    func discoverReciverCharacteristic(notti: CBPeripheral, colorService: CBService) -> CBCharacteristic? {
        let cbUUID = Delegator.colorReciverCBUUID

        if let reciver = colorService.characteristics?.first where reciver.UUID == cbUUID { return reciver }
        
        let semaphore = dispatch_semaphore_create(0)
        discoverReciverCharacteristicHandler = { dispatch_semaphore_signal(semaphore) }
        notti.discoverCharacteristics([cbUUID], forService: colorService)
        dispatch_semaphore_wait(semaphore, timeout)
        
        let reciver = colorService.characteristics?.first
        return reciver?.UUID == cbUUID ? reciver : nil
    }
    private var discoverReciverCharacteristicHandler: (() -> Void)?
    
    func write(notti: CBPeripheral, reciver: CBCharacteristic, data: NSData) -> Bool {
        var success = false
        
        let semaphore = dispatch_semaphore_create(0)
        writeHandler = { (error: NSError?) -> Void in
            success = error == nil
            dispatch_semaphore_signal(semaphore)
        }
        notti.writeValue(data, forCharacteristic: reciver, type: .WithResponse)
        dispatch_semaphore_wait(semaphore, timeout)
        
        return success
    }
    private var writeHandler: ((error: NSError?) -> Void)?
    
    func disconnect(notti: CBPeripheral) -> Bool {
        var success = false
        
        let semaphore = dispatch_semaphore_create(0)
        disconnectHandler = { (error: NSError?) -> Void in
            success = error == nil
            dispatch_semaphore_signal(semaphore)
        }
        centralManager.cancelPeripheralConnection(notti)
        dispatch_semaphore_wait(semaphore, timeout)
        
        return success
    }
    private var disconnectHandler: ((error: NSError?) -> Void)?
    
    // MARK: - CBCentralManagerDelegate
    
    internal func centralManagerDidUpdateState(central: CBCentralManager) {
        if verbose { print("Did change state. {\n\tcentral: \(central)\n}") }
        poweredOnHandler?()
    }
    
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        if verbose { print("Did discover peripheral. {\n\tperipheral: \(peripheral)\n}") }
        findNottiHandler?(peripheral: peripheral)
    }
    
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        if verbose { print("Did connect peripheral. {\n\tperipheral: \(peripheral)\n}") }
        connectHandler?()
    }
    
    internal func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        print("Did fail to connect peripehral. {\n\tperipheral: \(peripheral)\n\terror: \(error)\n}")
    }
    
    internal func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        if verbose { print("Did disconnect peripheral. {\n\tperipheral: \(peripheral)\n\terror: \(error)\n}") }
        disconnectHandler?(error: error)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if verbose { print("Did discover peripheral. {\n\tperipheral: \(peripheral)\n}") }
        discoverColorServiceHandler?()
    }
    
    internal func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        if verbose { print("Did discover characteristics. {\n\tservice: \(service)\n\terror: \(error)\n}") }
        discoverReciverCharacteristicHandler?()
    }
    
    internal func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if verbose { print("Did wirte characteristic. {\n\tcharacteristic: \(characteristic)\n\terror: \(error)\n}") }
        writeHandler?(error: error)
    }
}

internal struct Color {
    var red: UInt8 = 0x00
    var green: UInt8 = 0x00
    var blue: UInt8 = 0x00
    
    init(argument: String?) {
        guard let argument = argument else { return }
        
        var hex: UInt32 = 0
        if !NSScanner(string: argument).scanHexInt(&hex) { return }
        
        red = UInt8(hex >> 16)
        green = UInt8((hex >> 8) & 0xff)
        blue = UInt8(hex & 0xff)
    }
    
    var data: NSData {
        let bytes: [UInt8] = [0x06, 0x01, red, green, blue]
        if verbose { print("Create bytes. {\n\tbytes: \(bytes)\n}") }
        return NSData(bytes: bytes,
                      length: bytes.count)
    }
}

let centralManager = CBCentralManager(delegate: nil, queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
let delegator = Delegator(centralManager: centralManager)

if !delegator.poweredOn() {
    print("Failed to power on. state: \(centralManager.state.rawValue)")
    exit(#line)
}

guard let notti = delegator.findNotti else {
    print("Failed to find notti.")
    exit(#line)
}

if !delegator.connect(notti) {
    print("Failed to connect. {\n\tnotti: \(notti)\n}")
    exit(#line)
}

defer {
    if !delegator.disconnect(notti) {
        print("Failed to disconnect. {\n\tnotti: \(notti)\n}")
        exit(#line)
    }
    if verbose {
        print("Success. {\n\tnotti: \(notti)\n}")
    } else {
        print("Success.")
    }
}

guard let colorService = delegator.discoverColorService(notti) else {
    print("Failed to discover service. {\n\tnotti: \(notti)\n}")
    exit(#line)
}

if verbose { print("Discoverd service. {\n\tcolorService: \(colorService)\n}") }

guard let reciver = delegator.discoverReciverCharacteristic(notti, colorService: colorService) else {
    print("Failed to discover characteristic. {\n\tnotti: \(notti)\n\tcolorService: \(colorService)\n}")
    exit(#line)
}

if verbose { print("Discoverd reciver. {\n\treciver: \(reciver)\n}") }

let data = Color(argument: arguments.first).data
if verbose { print("Will write data {\n\tdata: \(data)\n}") }

if !delegator.write(notti, reciver: reciver, data: data) {
    print("Failed to write data. {\n\t(\(data))\n}")
    exit(#line)
}
