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
    
    fileprivate static let nottiUUID = UUID(uuidString: "3587105E-2D8C-4B57-8985-BD534EB44640")
    fileprivate static let colorServiceCBUUID = CBUUID(string: "FFF0")
    fileprivate static let colorReciverCBUUID = CBUUID(string: "FFF3")
    
    let centralManager: CBCentralManager
    
    override init() {
        centralManager = CBCentralManager(delegate: nil, queue: DispatchQueue.global())
        super.init()
        centralManager.delegate = self
    }
    
    // MARK: -
    
    fileprivate var timeout: DispatchTime { return DispatchTime.now() + Double(Int64(NSEC_PER_SEC*10)) / Double(NSEC_PER_SEC) }
    
    func poweredOn() -> Bool {
        if centralManager.state == .poweredOn { return true }
        
        let semaphore = DispatchSemaphore(value: 0)
        poweredOnHandler = { [weak self] in
            self?.poweredOnHandler = nil
            semaphore.signal()
        }
        if case .timedOut = semaphore.wait(timeout: timeout) { return false }
        
        return centralManager.state == .poweredOn
    }
    fileprivate var poweredOnHandler: (() -> Void)?
    
    var findNotti: CBPeripheral? {
        let cbUUID = BLEClient.colorServiceCBUUID
        
        if let notti = centralManager.retrieveConnectedPeripherals(withServices: [cbUUID]).first {
            if verbose { print("Retrive peripheral. {\n\tnotti: \(notti)\n}") }
            notti.delegate = self
            return notti
        }
        
        var notti: CBPeripheral?
        
        let semaphore = DispatchSemaphore(value: 0)
        findNottiHandler = { [weak self] (peripheral: CBPeripheral) in
            if peripheral.identifier == BLEClient.nottiUUID {
                if verbose { print("Found notti. {\n\tnotti: \(peripheral)\n}") }
                notti = peripheral
                self?.findNottiHandler = nil
                semaphore.signal()
            }
        }
        centralManager.scanForPeripherals(withServices: [cbUUID], options: nil)
        defer { centralManager.stopScan() }
        
        if case .timedOut = semaphore.wait(timeout: timeout) { return nil }
        
        notti?.delegate = self
        return notti
    }
    fileprivate var findNottiHandler: ((_ peripheral: CBPeripheral) -> Void)?
    
    func connect(_ peripheral: CBPeripheral) -> Bool {
        if peripheral.state == .connected { return true }
        
        let semaphore = DispatchSemaphore(value: 0)
        connectHandler = { [weak self] in
            self?.connectHandler = nil
            semaphore.signal()
        }
        centralManager.connect(peripheral, options: nil)
        
        if case .timedOut = semaphore.wait(timeout: timeout) { return false }
        
        return peripheral.state == .connected
    }
    fileprivate var connectHandler: (() -> Void)?
    
    func discoverColorService(_ notti: CBPeripheral) -> CBService? {
        let cbUUID = BLEClient.colorServiceCBUUID
        
        if let service = notti.services?.first, service.uuid == cbUUID {
            return service
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        discoverColorServiceHandler = { [weak self] in
            self?.discoverColorServiceHandler = nil
            semaphore.signal()
        }
        notti.discoverServices([cbUUID])
        
        if case .timedOut = semaphore.wait(timeout: timeout) { return nil }
        
        let service = notti.services?.first
        return service?.uuid == cbUUID ? service : nil
    }
    fileprivate var discoverColorServiceHandler: (() -> Void)?
    
    func discoverReciverCharacteristic(_ notti: CBPeripheral, colorService: CBService) -> CBCharacteristic? {
        let cbUUID = BLEClient.colorReciverCBUUID
        
        if let reciver = colorService.characteristics?.first, reciver.uuid == cbUUID {
            return reciver
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        discoverReciverCharacteristicHandler = { [weak self] in
            self?.discoverReciverCharacteristicHandler = nil
            semaphore.signal()
        }
        notti.discoverCharacteristics([cbUUID], for: colorService)
        
        if case .timedOut = semaphore.wait(timeout: timeout) { return nil }
        
        let reciver = colorService.characteristics?.first
        return reciver?.uuid == cbUUID ? reciver : nil
    }
    fileprivate var discoverReciverCharacteristicHandler: (() -> Void)?
    
    func write(_ notti: CBPeripheral, reciver: CBCharacteristic, data: Data) -> Bool {
        var success = false
        
        let semaphore = DispatchSemaphore(value: 0)
        writeHandler = { [weak self] (error: NSError?) in
            success = error == nil
            self?.writeHandler = nil
            semaphore.signal()
        }
        notti.writeValue(data, for: reciver, type: .withResponse)
        
        if case .timedOut = semaphore.wait(timeout: timeout) { return false }
        
        return success
    }
    fileprivate var writeHandler: ((_ error: NSError?) -> Void)?
    
    func disconnect(_ notti: CBPeripheral) -> Bool {
        var success = false
        
        let semaphore = DispatchSemaphore(value: 0)
        disconnectHandler = { [weak self] (error: NSError?) in
            success = error == nil
            self?.disconnectHandler = nil
            semaphore.signal()
        }
        centralManager.cancelPeripheralConnection(notti)
        
        if case .timedOut = semaphore.wait(timeout: timeout) { return false }
        
        return success
    }
    fileprivate var disconnectHandler: ((_ error: NSError?) -> Void)?
    
    // MARK: - CBCentralManagerDelegate
    
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if verbose { print("\(#function) {\n\tcentral.state: \(central.state.rawValue)\n}") }
        poweredOnHandler?()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if verbose { print("\(#function) {\n\tperipheral: \(peripheral)\n}") }
        findNottiHandler?(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if verbose { print("\(#function) {\n\tperipheral: \(peripheral)\n}") }
        connectHandler?()
    }
    
    internal func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("\(#function) {\n\tperipheral: \(peripheral)\n\terror: \(String(describing: error))\n}")
    }
    
    internal func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if verbose { print("\(#function) {\n\tperipheral: \(peripheral)\n\terror: \(String(describing: error))\n}") }
        disconnectHandler?(error as NSError?)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if verbose { print("\(#function) {\n\tperipheral: \(peripheral)\n}") }
        discoverColorServiceHandler?()
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if verbose { print("\(#function) {\n\tservice: \(service)\n\tservice.characteristics: \(String(describing: service.characteristics))\n\terror: \(String(describing: error))\n}") }
        discoverReciverCharacteristicHandler?()
    }
    
    internal func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if verbose { print("Did wirte characteristic. {\n\tcharacteristic: \(characteristic)\n\terror: \(String(describing: error))\n}") }
        writeHandler?(error as NSError?)
    }
}
