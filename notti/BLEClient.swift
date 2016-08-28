//
//  BLEClient.swift
//  notti
//
//  Created by Yu Sugawara on 8/28/16.
//  Copyright © 2016 Yu Sugawara. All rights reserved.
//

import Foundation
import CoreBluetooth

internal class BLEClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private static let nottiUUID = NSUUID(UUIDString: "B1C06DCE-8935-4E0D-8AED-8432F2DBC73C")
    private static let colorServiceCBUUID = CBUUID(string: "FFF0")
    private static let colorReciverCBUUID = CBUUID(string: "FFF3")
    
    let centralManager: CBCentralManager
    
    override init() {
        centralManager = CBCentralManager(delegate: nil, queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        super.init()
        centralManager.delegate = self
    }
    
    // MARK: -
    
    private var timeout: dispatch_time_t { return dispatch_time(DISPATCH_TIME_NOW, Int64(NSEC_PER_SEC*10)) }
    
    func poweredOn() -> Bool {
        if centralManager.state == .PoweredOn { return true }
        
        let semaphore = dispatch_semaphore_create(0)
        poweredOnHandler = { [weak self] in
            self?.poweredOnHandler = nil
            dispatch_semaphore_signal(semaphore)
        }
        dispatch_semaphore_wait(semaphore, timeout)
        
        return centralManager.state == .PoweredOn
    }
    private var poweredOnHandler: (() -> Void)?
    
    var findNotti: CBPeripheral? {
        let cbUUID = BLEClient.colorServiceCBUUID
        
        if let notti = centralManager.retrieveConnectedPeripheralsWithServices([cbUUID]).first {
            if verbose { print("Retrive peripheral. {\n\tnotti: \(notti)\n}") }
            notti.delegate = self
            return notti
        }
        
        var notti: CBPeripheral?
        
        let semaphore = dispatch_semaphore_create(0)
        findNottiHandler = { [weak self] (peripheral: CBPeripheral) in
            if peripheral.identifier == BLEClient.nottiUUID {
                if verbose { print("Found notti. {\n\tnotti: \(peripheral)\n}") }
                notti = peripheral
                self?.findNottiHandler = nil
                dispatch_semaphore_signal(semaphore)
            }
        }
        centralManager.scanForPeripheralsWithServices([cbUUID], options: nil)
        dispatch_semaphore_wait(semaphore, timeout)
        centralManager.stopScan()
        
        notti?.delegate = self
        return notti
    }
    private var findNottiHandler: ((peripheral: CBPeripheral) -> Void)?
    
    func connect(peripheral: CBPeripheral) -> Bool {
        if peripheral.state == .Connected { return true }
        
        let semaphore = dispatch_semaphore_create(0)
        connectHandler = { [weak self] in
            self?.connectHandler = nil
            dispatch_semaphore_signal(semaphore)
        }
        centralManager.connectPeripheral(peripheral, options: nil)
        dispatch_semaphore_wait(semaphore, timeout)
        
        return peripheral.state == .Connected
    }
    private var connectHandler: (() -> Void)?
    
    func discoverColorService(notti: CBPeripheral) -> CBService? {
        let cbUUID = BLEClient.colorServiceCBUUID
        
        if let service = notti.services?.first where service.UUID == cbUUID {
            return service
        }
        
        let semaphore = dispatch_semaphore_create(0)
        discoverColorServiceHandler = { [weak self] in
            self?.discoverColorServiceHandler = nil
            dispatch_semaphore_signal(semaphore)
        }
        notti.discoverServices([cbUUID])
        dispatch_semaphore_wait(semaphore, timeout)
        
        let service = notti.services?.first
        return service?.UUID == cbUUID ? service : nil
    }
    private var discoverColorServiceHandler: (() -> Void)?
    
    func discoverReciverCharacteristic(notti: CBPeripheral, colorService: CBService) -> CBCharacteristic? {
        let cbUUID = BLEClient.colorReciverCBUUID
        
        if let reciver = colorService.characteristics?.first where reciver.UUID == cbUUID {
            return reciver
        }
        
        let semaphore = dispatch_semaphore_create(0)
        discoverReciverCharacteristicHandler = { [weak self] in
            self?.discoverReciverCharacteristicHandler = nil
            dispatch_semaphore_signal(semaphore)
        }
        notti.discoverCharacteristics([cbUUID], forService: colorService)
        dispatch_semaphore_wait(semaphore, timeout)
        
        let reciver = colorService.characteristics?.first
        return reciver?.UUID == cbUUID ? reciver : nil
    }
    private var discoverReciverCharacteristicHandler: (() -> Void)?
    
    func write(notti: CBPeripheral, reciver: CBCharacteristic, data: NSData) -> Bool {
        var success = false
        
        let semaphore = dispatch_semaphore_create(0)
        writeHandler = { [weak self] (error: NSError?) in
            success = error == nil
            self?.writeHandler = nil
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
        disconnectHandler = { [weak self] (error: NSError?) in
            success = error == nil
            self?.disconnectHandler = nil
            dispatch_semaphore_signal(semaphore)
        }
        centralManager.cancelPeripheralConnection(notti)
        dispatch_semaphore_wait(semaphore, timeout)
        
        return success
    }
    private var disconnectHandler: ((error: NSError?) -> Void)?
    
    // MARK: - CBCentralManagerDelegate
    
    internal func centralManagerDidUpdateState(central: CBCentralManager) {
        if verbose { print("Did change state. {\n\tcentral.state: \(central.state.rawValue)\n}") }
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
        if verbose { print("Did discover characteristics. {\n\tservice: \(service)\n\tservice.characteristics: \(service.characteristics)\n\terror: \(error)\n}") }
        discoverReciverCharacteristicHandler?()
    }
    
    internal func peripheral(peripheral: CBPeripheral, didWriteValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if verbose { print("Did wirte characteristic. {\n\tcharacteristic: \(characteristic)\n\terror: \(error)\n}") }
        writeHandler?(error: error)
    }
}