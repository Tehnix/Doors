/*

Copyright (c) 2015 Fernando Reynoso

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/
import Foundation
import CoreBluetooth

protocol BLEDelegate {
    func bleDidUpdateState()
    func bleDidConnectToPeripheral()
    func bleDidDisconenctFromPeripheral()
    func bleDidReceiveData(data: NSData?)
}

class BLE: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // The service values for the Red Bear Lab BLE shield
    let RBL_SERVICE_UUID = "713D0000-503E-4C75-BA94-3148F18D941E"
    let RBL_CHAR_TX_UUID = "713D0002-503E-4C75-BA94-3148F18D941E"
    let RBL_CHAR_RX_UUID = "713D0003-503E-4C75-BA94-3148F18D941E"

    var delegate: BLEDelegate?
    var peripheralRSSI = [CBPeripheral: NSNumber]()

    private      var centralManager:   CBCentralManager!
    private      var activePeripheral: CBPeripheral?
    private      var characteristics = [String : CBCharacteristic]()
    private      var data:             NSMutableData?
    private(set) var peripherals     = [CBPeripheral]()
    private      var RSSICompletionHandler: ((NSNumber?, NSError?) -> ())?

    override init() {
        super.init()
        // Set up the central manager object, marking the class itself as the
        // delegate to use
        self.centralManager = CBCentralManager(delegate: self, queue: nil)
        self.data = NSMutableData()
    }

    @objc private func scanTimeout() {
        // Stop the central manager from scanning repeatedly
        print("[DEBUG] Scanning stopped")
        self.centralManager.stopScan()
    }

    // MARK: Public methods
    func startScanning(timeout: Double) -> Bool {
        if self.centralManager.state != .PoweredOn {
            // If the central manager isn't on, then it's not possible to scan
            // yet
            print("[ERROR] Couldn´t start scanning")
            return false
        } else if self.centralManager.isScanning {
            // If the central manager is already scanning, then it's not
            // neccessary to initiate the scan again
            print("[DEBUG] Already scanning")
            return false
        }

        print("[DEBUG] Scanning started")
        // Set the scanner to stop after a set timeout value
        NSTimer.scheduledTimerWithTimeInterval(timeout, target: self, selector: Selector("scanTimeout"), userInfo: nil, repeats: false)

        // Start scanning for the specific service
        let services:[CBUUID] = [CBUUID(string: RBL_SERVICE_UUID)]
        self.centralManager.scanForPeripheralsWithServices(services, options: nil)
        return true
    }

    func connectToPeripheral(peripheral: CBPeripheral) -> Bool {
        if self.centralManager.state != .PoweredOn {
            // If the central manager isn't on, then it's not possible to scan
            // yet
            print("[ERROR] Couldn´t connect to peripheral")
            return false
        }

        // Connect to the actual peripheral
        print("[DEBUG] Connecting to peripheral: \(peripheral.identifier.UUIDString)")
        self.centralManager.connectPeripheral(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey : NSNumber(bool: true)])
        return true
    }

    func disconnectFromPeripheral(peripheral: CBPeripheral) -> Bool {
        if self.centralManager.state != .PoweredOn {
            // If the central manager isn't on, then it's not possible to scan
            // yet
            print("[ERROR] Couldn´t disconnect from peripheral")
            return false
        }

        // Disconnect from the peripheral
        self.centralManager.cancelPeripheralConnection(peripheral)
        return true
    }

    func read() {
        // Read values from the currently active peripheral
        self.activePeripheral?.readValueForCharacteristic(self.characteristics[RBL_CHAR_TX_UUID]!)
    }

    func write(data: NSData) {
        // Write values to the BLE peripheral
        if let characteristics = self.characteristics[RBL_CHAR_RX_UUID] {
            self.activePeripheral?.writeValue(data, forCharacteristic: characteristics, type: .WithoutResponse)
        } else {
            print("[DEBUG] Failed to unwrap characteristics")
        }
    }

    func enableNotifications(enable: Bool) {
        self.activePeripheral?.setNotifyValue(enable, forCharacteristic: self.characteristics[RBL_CHAR_TX_UUID]!)
    }

    func readRSSI(completion: (RSSI: NSNumber?, error: NSError?) -> ()) {
        self.RSSICompletionHandler = completion
        self.activePeripheral?.readRSSI()
    }

    // MARK: CBCentralManager delegate
    func centralManagerDidUpdateState(central: CBCentralManager) {
        switch central.state {
        case .Unknown:
            print("[DEBUG] Central manager state: Unknown")
            break

        case .Resetting:
            print("[DEBUG] Central manager state: Resseting")
            break

        case .Unsupported:
            print("[DEBUG] Central manager state: Unsopported")
            break

        case .Unauthorized:
            print("[DEBUG] Central manager state: Unauthorized")
            break

        case .PoweredOff:
            print("[DEBUG] Central manager state: Powered off")
            break

        case .PoweredOn:
            print("[DEBUG] Central manager state: Powered on")
            break
        }

        self.delegate?.bleDidUpdateState()
    }

    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        // When the central manager discovers a peripherals, it calls this
        // method with the peripheral information
        print("[DEBUG] Found peripheral: \(peripheral.identifier.UUIDString) RSSI: \(RSSI)")
        for var i = 0; i < self.peripherals.count; i++ {
            let p = self.peripherals[i] as CBPeripheral
            if p.identifier.UUIDString == peripheral.identifier.UUIDString {
                self.peripherals[i] = peripheral
                return
            }
        }
        // Keep track of all the peripherals and their RSSI
        self.peripherals.append(peripheral)
        self.peripheralRSSI[peripheral] = RSSI
    }

    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        // In case the peripheral connection fails, this method can be used to
        // clean up after it
        print("[ERROR] Could not connect to peripheral \(peripheral.identifier.UUIDString) error: \(error!.description)")
    }

    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        // Upon successfully connecting to a peripheral, the active peripheral
        // is saved
        print("[DEBUG] Connected to peripheral \(peripheral.identifier.UUIDString)")
        self.activePeripheral = peripheral
        self.activePeripheral?.delegate = self
        self.activePeripheral?.discoverServices([CBUUID(string: RBL_SERVICE_UUID)])
        self.delegate?.bleDidConnectToPeripheral()
    }

    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        var text = "[DEBUG] Disconnected from peripheral: \(peripheral.identifier.UUIDString)"
        if error != nil {
            text += ". Error: \(error!.description)"
        }
        print(text)
        self.activePeripheral?.delegate = nil
        self.activePeripheral = nil
        self.characteristics.removeAll(keepCapacity: false)
        self.delegate?.bleDidDisconenctFromPeripheral()
    }

    // MARK: CBPeripheral delegate
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if error != nil {
            print("[ERROR] Error discovering services. \(error!.description)")
            return
        }
        print("[DEBUG] Found services for peripheral: \(peripheral.identifier.UUIDString)")
        for service in peripheral.services as [CBService]! {
            let theCharacteristics = [CBUUID(string: RBL_CHAR_RX_UUID), CBUUID(string: RBL_CHAR_TX_UUID)]
            peripheral.discoverCharacteristics(theCharacteristics, forService: service)
        }
    }

    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        if error != nil {
            print("[ERROR] Error discovering characteristics. \(error!.description)")
            return
        }
        print("[DEBUG] Found characteristics for peripheral: \(peripheral.identifier.UUIDString)")

        for characteristic in service.characteristics as [CBCharacteristic]! {
            self.characteristics[characteristic.UUID.UUIDString] = characteristic
        }
        enableNotifications(true)
    }

    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        if error != nil {
            print("[ERROR] Error updating value. \(error!.description)")
            return
        }
        if characteristic.UUID.UUIDString == RBL_CHAR_TX_UUID {
            self.delegate?.bleDidReceiveData(characteristic.value)
        }
    }

    func peripheral(peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: NSError?) {
        self.RSSICompletionHandler?(RSSI, error)
        self.RSSICompletionHandler = nil
    }
}
