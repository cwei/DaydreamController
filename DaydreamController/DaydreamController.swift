//  Supports the Google VR Daydream View Controller on iOS.
//
//  DaydreamController.swift
//
//  Created by cwei@bytonic.de
//  Copyright © 2016 Carsten Weiße. All rights reserved.

/*
Create a new iOS Game project (SceneKit) with Xcode, add this class
and modify GameViewController.swift like this:

class GameViewController: UIViewController
{
    let controller = DaydreamController()
    var ship: SCNNode!
    var orientation0 = GLKQuaternionIdentity
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        controller.delegate = self
        controller.connect()
            
        ....
            
        // retrieve the ship node
        ship = scene.rootNode.childNode(withName: "ship", recursively: true)!

        // animate the 3d object
        // ship.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 2, z: 0, duration: 1)))
        ....
    }
}

extension GameViewController: DaydreamControllerDelegate
{
    func daydreamControllerDidConnect(_ controller: DaydreamController) {
        print("Press the home button to recenter the controller's orientation")
    }
    
    func daydreamControllerDidUpdate(_ controller: DaydreamController, state: DaydreamController.State) {
        if state.homeButtonDown {
            orientation0 = GLKQuaternionInvert(state.orientation)
        }
        
        let q = GLKQuaternionMultiply(orientation0 ,state.orientation)
        ship.orientation = SCNQuaternion(q.x, q.y, q.z, q.w)
    }
}
*/

import Foundation
import CoreBluetooth
import GLKit

class DaydreamController: NSObject
{
    let DAYDREAM_NAME = "Daydream controller"
    let DAYDREAM_SERVICE = CBUUID(string: "0000fe55-0000-1000-8000-00805f9b34fb")
    let DAYDREAM_CHARACTERISTIC = CBUUID(string: "00000001-1000-1000-8000-00805f9b34fb")
    
    let BATTERY_SERVICE = CBUUID(string: "180F")
    let BATTERY_LEVEL_CHARACTERISTIC = CBUUID(string: "2A19")
    
    var delegate: DaydreamControllerDelegate?
    fileprivate(set) var batteryLevel: UInt8? = nil // 0 - 100%

    // bluetooth low energy
    fileprivate var manager: CBCentralManager!
    fileprivate var peripheral: CBPeripheral?
    fileprivate var characteristic: CBCharacteristic?
    fileprivate var batteryLevelCharacteristic: CBCharacteristic?
    // controller sensor, touch pad and buttons state
    fileprivate var prevState = State()
    fileprivate var state = State()
    
    var connected: Bool {
        return .connected == (peripheral?.state ?? .disconnected)
    }
    
    func connect() {
        if nil == manager {
            let managerQ = DispatchQueue(label: "vr.daydreamcontroller", qos: .userInteractive)
            manager = CBCentralManager(delegate: self, queue: managerQ)
        }
        
        if let peripheral = peripheral {
            if .disconnected == peripheral.state {
                manager.connect(peripheral, options: nil)
                print("\(peripheral.name!) \(peripheral.state)")
            } else {
                resume()
            }
        }
    }
    
    func pause() {
        setNotifyValues(false)
    }
    
    func resume() {
        setNotifyValues(true)
    }
    
    func disconnect() {
        pause()
        if let peripheral = peripheral {
            manager?.cancelPeripheralConnection(peripheral)
        }
    }
    
    private func setNotifyValues(_ enabled: Bool) {
        if let characteristic = characteristic {
            peripheral?.setNotifyValue(enabled, for: characteristic)
        }
        
        if let batteryLevelCharacteristic = batteryLevelCharacteristic {
            peripheral?.setNotifyValue(enabled, for: batteryLevelCharacteristic)
        }
    }
    
    
    struct State
    {
        let timestamp: UInt16 // 0 - 511 ms
        let seq: UInt8 // 0 - 31
        let orientation: GLKQuaternion // A quaternion representing the local controller orientation.
        let accel: (Float, Float, Float) // m/(s*s)
        let gyro: (Float, Float, Float) // unit = rad/s
        
        let touchPos: (Float, Float) // upper left (0.0, 0.0) - (1.0, 1.0) bottom right
        let isTouching: Bool
        
        let clickButton: Bool
        let homeButton: Bool
        let appButton: Bool
        let plusButton: Bool
        let minusButton: Bool
        
        // transient events
        let touchUp: Bool
        let touchDown: Bool
        let clickButtonUp: Bool
        let clickButtonDown: Bool
        let homeButtonUp: Bool
        let homeButtonDown: Bool
        let appButtonUp: Bool
        let appButtonDown: Bool
        let plusButtonUp: Bool
        let plusButtonDown: Bool
        let minusButtonUp: Bool
        let minusButtonDown: Bool
        
        init() {
            timestamp = 0
            seq = 0
            orientation = GLKQuaternionIdentity
            accel = (0, 0, 0)
            gyro = (0, 0, 0)
            
            touchPos = (0, 0)
            isTouching = false
            
            clickButton = false
            homeButton = false
            appButton = false
            plusButton = false
            minusButton = false
            
            touchUp = false
            touchDown = false
            clickButtonUp = false
            clickButtonDown = false
            homeButtonUp = false
            homeButtonDown = false
            appButtonUp = false
            appButtonDown = false
            plusButtonUp = false
            plusButtonDown = false
            minusButtonUp = false
            minusButtonDown = false
        }
        
        fileprivate init(_ data: Data, prev: State) {
            /*
             * parse the 20 bytes data package
             */
            timestamp = UInt16(data[0]) << 1 | UInt16(data[1]) >> 7 // timestamp in ms [0; 511] every 16 ms arrives a data package
            seq = (data[1] & 0b01111100) >> 2 // sequence range [0; 31]
            // raw orientation 13 bit signed int
            let ox = Int16(bitPattern: (UInt16(data[1]) << 14) | (UInt16(data[2]) << 6) | (UInt16(data[3] & 0b11100000) >> 2)) >> 3
            let oy = Int16(bitPattern: (UInt16(data[3]) << 11) | (UInt16(data[4]) << 3)) >> 3
            let oz = Int16(bitPattern: (UInt16(data[5]) <<  8) | (UInt16(data[6] & 0b11111000))) >> 3
            // raw accelerometer 13 bit signed int
            let ax = Int16(bitPattern: (UInt16(data[6]) << 13) | (UInt16(data[7]) << 5) | (UInt16(data[8] & 0b11000000) >> 1)) >> 3
            let ay = Int16(bitPattern: (UInt16(data[8]) << 10) | (UInt16(data[9] & 0b11111110) << 2)) >> 3
            let az = Int16(bitPattern: (UInt16(data[9]) << 15) | (UInt16(data[10]) << 7) | (UInt16(data[11] & 0b11110000) >> 1)) >> 3
            // raw gyroscope 13 bit signed int, unit = 0.5 * degrees per second
            let gx = Int16(bitPattern: (UInt16(data[11]) << 12) | (UInt16(data[12]) << 4) | (UInt16(data[13] & 0b10000000) >> 4)) >> 3
            let gy = Int16(bitPattern: (UInt16(data[13]) <<  9) | (UInt16(data[14] & 0b11111100) << 1)) >> 3
            let gz = Int16(bitPattern: (UInt16(data[14]) << 14) | (UInt16(data[15]) << 6) | (UInt16(data[16] & 0b11100000) >> 2)) >> 3
            // touchpad x, y with 0 - 255
            let tx = (data[16] << 3) | (data[17] >> 5)
            let ty = (data[17] << 3) | (data[18] >> 5)
            // buttons
            let buttonFlags = data[18] & 0b00011111
            // last byte unknown or reserved
            
            do {
                // orientation is represented as axis-angles with magnitude as rotation angle theta around that vector
                let scale = Float(2.0 * .pi / 4095.0)
                let x = Float(ox) * scale
                let y = Float(oy) * scale
                let z = Float(oz) * scale
                
                let magnitudeSquare = x * x + y * y + z * z
                
                if (0.0 < magnitudeSquare) {
                    let magnitude = sqrt(magnitudeSquare) // same as axis angle
                    let scale = 1.0 / magnitude
                    orientation = GLKQuaternionMakeWithAngleAndAxis(magnitude, x * scale, y * scale, z * scale)
                } else {
                    orientation = GLKQuaternionIdentity
                }
            }
            
            do {
                let scale = Float(9.8 * 8.0 / 4095.0)
                accel = (Float(ax) * scale, Float(ay) * scale, Float(az) * scale)
            }
            
            do {
                let scale = Float(.pi * 2048.0 / 4095.0 / 180.0)
                gyro = (Float(gx) * scale, Float(gy) * scale, Float(gz) * scale)
            }
            
            touchPos = (Float(tx) / 255.0, Float(ty) / 255.0) // The touch position from upper left (0, 0) to lower right (1, 1).
            isTouching = (0 < tx || 0 < ty)
            
            clickButton = (0 < (buttonFlags & 0b00001))
            homeButton  = (0 < (buttonFlags & 0b00010))
            appButton   = (0 < (buttonFlags & 0b00100))
            plusButton  = (0 < (buttonFlags & 0b01000))
            minusButton = (0 < (buttonFlags & 0b10000))
            // transient events
            touchUp         = (!isTouching && prev.isTouching)
            touchDown       = (isTouching && !prev.isTouching)
            clickButtonUp   = (!clickButton && prev.clickButton)
            clickButtonDown = (clickButton && !prev.clickButton)
            homeButtonUp    = (!homeButton && prev.homeButton)
            homeButtonDown  = (homeButton && !prev.homeButton)
            appButtonUp     = (!appButton && prev.appButton)
            appButtonDown   = (appButton && !prev.appButton)
            plusButtonUp    = (!plusButton && prev.plusButton)
            plusButtonDown  = (plusButton && !prev.plusButton)
            minusButtonUp   = (!minusButton && prev.minusButton)
            minusButtonDown = (minusButton && !prev.minusButton)
        }
    }
}

protocol DaydreamControllerDelegate
{
    func daydreamControllerDidConnect(_ controller: DaydreamController)
    
    func daydreamControllerDidUpdate(_ controller: DaydreamController, state: DaydreamController.State)
}

extension DaydreamController: CBCentralManagerDelegate
{
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        } else {
            print("Bluetooth not available.")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let device = (advertisementData as NSDictionary).object(forKey: CBAdvertisementDataLocalNameKey) as? NSString
        
        if true == device?.contains(DAYDREAM_NAME) {
            self.manager.stopScan()
            print("\(peripheral.name!) found")
            self.peripheral = peripheral
            self.peripheral?.delegate = self
            
            self.manager.connect(peripheral, options: nil)
            print("\(peripheral.name!) \(peripheral.state)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("\(peripheral.name!) \(peripheral.state)")
        DispatchQueue.main.async {
            self.delegate?.daydreamControllerDidConnect(self)
        }
        peripheral.discoverServices([DAYDREAM_SERVICE, BATTERY_SERVICE])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("\(peripheral.name!) \(peripheral.state)")
    }
}

extension DaydreamController: CBPeripheralDelegate
{
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: NSError?) {
        print("Error connecting peripheral: \(error?.localizedDescription)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            print("Error discovering services: \(error?.localizedDescription)")
        }
        
        peripheral.services?.forEach { (service) in
            if DAYDREAM_SERVICE == service.uuid {
                peripheral.discoverCharacteristics([DAYDREAM_CHARACTERISTIC], for: service)
            } else if BATTERY_SERVICE == service.uuid {
                peripheral.discoverCharacteristics([BATTERY_LEVEL_CHARACTERISTIC], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if error != nil {
            print("Error discovering service characteristics: \(error?.localizedDescription)")
        }
        
        service.characteristics?.forEach { (characteristic) in
            if DAYDREAM_CHARACTERISTIC == characteristic.uuid {
                self.characteristic = characteristic
                self.peripheral?.setNotifyValue(true, for: characteristic)
                print("\(peripheral.name!) sensor notifications on")
            } else if BATTERY_LEVEL_CHARACTERISTIC == characteristic.uuid {
                self.batteryLevelCharacteristic = characteristic
                self.peripheral?.readValue(for: characteristic) // read first value
                self.peripheral?.setNotifyValue(true, for: characteristic) // only if level changes
                print("\(peripheral.name!) battery notifications on")
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if error != nil {
            print("Error updating characteristic: \(error?.localizedDescription)")
        }
        
        if characteristic == self.characteristic {
            guard let sensorData = characteristic.value, 20 == sensorData.count else {
                return
            }
            
            let newState = State(sensorData, prev: state)
            self.prevState = state
            self.state = newState
            
            DispatchQueue.main.async {
                self.delegate?.daydreamControllerDidUpdate(self, state: newState)
            }
        } else if characteristic == self.batteryLevelCharacteristic {
            guard let batteryData = characteristic.value, 1 == batteryData.count else {
                return
            }

            self.batteryLevel = batteryData[0]
        }
    }
}

extension CBPeripheralState: CustomStringConvertible
{
    public var description: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        }
    }
}
