import CoreBluetooth
import Foundation

@MainActor
final class CoreBluetoothElephSetupService: NSObject, ElephSetupBluetoothService {
    static let setupServiceUUID = CBUUID(string: "E1E10001-4B18-4F7D-9D25-000000000001")
    static let setupStatusCharacteristicUUID = CBUUID(string: "E1E10002-4B18-4F7D-9D25-000000000001")
    static let provisioningPayloadCharacteristicUUID = CBUUID(string: "E1E10003-4B18-4F7D-9D25-000000000001")

    private lazy var centralManager = CBCentralManager(delegate: self, queue: .main)
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var setupStatusCharacteristic: CBCharacteristic?
    private var provisioningPayloadCharacteristic: CBCharacteristic?

    private var bluetoothPowerContinuation: CheckedContinuation<Void, Error>?
    private var scanContinuation: CheckedContinuation<[SetupDevice], Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private var statusReadContinuation: CheckedContinuation<SetupStatus, Error>?
    private var provisioningReadContinuation: CheckedContinuation<ProvisioningStatus, Error>?
    private var writeContinuation: CheckedContinuation<Void, Error>?
    private var scanResults: [SetupDevice] = []

    func scanForSetupDevices() async throws -> [SetupDevice] {
        try await waitForBluetoothPoweredOn()

        discoveredPeripherals.removeAll()
        scanResults.removeAll()

        return try await withCheckedThrowingContinuation { continuation in
            scanContinuation = continuation
            centralManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                completeScanIfNeeded()
            }
        }
    }

    func connect(to setupDevice: SetupDevice) async throws {
        guard let peripheral = discoveredPeripherals[setupDevice.id] else {
            throw AppServiceError.validation("That Eleph monitor is no longer available. Try scanning again.")
        }

        try await waitForBluetoothPoweredOn()
        connectedPeripheral = peripheral
        setupStatusCharacteristic = nil
        provisioningPayloadCharacteristic = nil
        peripheral.delegate = self

        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            centralManager.connect(peripheral, options: nil)
        }
    }

    func readSetupStatus() async throws -> SetupStatus {
        guard let peripheral = connectedPeripheral, let characteristic = setupStatusCharacteristic else {
            throw AppServiceError.validation("Bluetooth setup status is not available.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            statusReadContinuation = continuation
            peripheral.readValue(for: characteristic)
        }
    }

    func sendProvisioningPayload(_ payload: ProvisioningPayload) async throws {
        guard let peripheral = connectedPeripheral, let characteristic = provisioningPayloadCharacteristic else {
            throw AppServiceError.validation("Bluetooth provisioning is not available.")
        }

        let data = try JSONEncoder.elephBluetooth.encode(payload) + Data([0x0A])
        let chunkSize = max(peripheral.maximumWriteValueLength(for: .withResponse), 20)

        var offset = 0
        while offset < data.count {
            let nextOffset = min(offset + chunkSize, data.count)
            let chunk = data[offset..<nextOffset]
            try await write(chunk, to: characteristic, on: peripheral)
            offset = nextOffset
        }
    }

    func observeProvisioningStatus() async throws -> ProvisioningStatus {
        guard let peripheral = connectedPeripheral, let characteristic = setupStatusCharacteristic else {
            throw AppServiceError.validation("Bluetooth setup status is not available.")
        }

        if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: characteristic)
        }

        let deadline = Date().addingTimeInterval(60)
        var latestStatus: ProvisioningStatus = .receivingPayload

        while Date() < deadline {
            latestStatus = try await readProvisioningStatus(from: characteristic, on: peripheral)
            if latestStatus == .online || latestStatus == .failed {
                return latestStatus
            }
            try await Task.sleep(for: .seconds(1))
        }

        throw AppServiceError.validation("Timed out waiting for the monitor to finish Wi-Fi setup.")
    }

    private func waitForBluetoothPoweredOn() async throws {
        _ = centralManager

        switch centralManager.state {
        case .poweredOn:
            return
        case .poweredOff:
            throw AppServiceError.validation("Turn on Bluetooth to set up an Eleph monitor.")
        case .unauthorized:
            throw AppServiceError.validation("Allow Bluetooth access for Eleph in Settings.")
        case .unsupported:
            throw AppServiceError.validation("This device does not support Bluetooth setup.")
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }

        try await withCheckedThrowingContinuation { continuation in
            bluetoothPowerContinuation = continuation

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                if let bluetoothPowerContinuation {
                    self.bluetoothPowerContinuation = nil
                    bluetoothPowerContinuation.resume(
                        throwing: AppServiceError.validation("Bluetooth is not ready yet. Try again.")
                    )
                }
            }
        }
    }

    private func completeScanIfNeeded() {
        guard let scanContinuation else { return }
        centralManager.stopScan()
        self.scanContinuation = nil

        let sortedResults = scanResults.sorted { $0.signalStrength > $1.signalStrength }
        if sortedResults.isEmpty {
            scanContinuation.resume(throwing: AppServiceError.validation("No nearby Eleph monitors were found."))
        } else {
            scanContinuation.resume(returning: sortedResults)
        }
    }

    private func write(_ data: Data.SubSequence, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { continuation in
            writeContinuation = continuation
            peripheral.writeValue(Data(data), for: characteristic, type: .withResponse)
        }
    }

    private func readProvisioningStatus(from characteristic: CBCharacteristic, on peripheral: CBPeripheral) async throws -> ProvisioningStatus {
        try await withCheckedThrowingContinuation { continuation in
            provisioningReadContinuation = continuation
            peripheral.readValue(for: characteristic)
        }
    }

    private func decodeSetupStatus(from data: Data?) -> SetupStatus {
        guard let rawValue = string(from: data) else { return .unknown }
        return SetupStatus(rawValue: rawValue) ?? .unknown
    }

    private func decodeProvisioningStatus(from data: Data?) -> ProvisioningStatus {
        guard let rawValue = string(from: data) else { return .idle }
        return ProvisioningStatus(rawValue: rawValue) ?? .idle
    }

    private func string(from data: Data?) -> String? {
        guard let data,
              let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

extension CoreBluetoothElephSetupService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let bluetoothPowerContinuation else { return }

        switch central.state {
        case .poweredOn:
            self.bluetoothPowerContinuation = nil
            bluetoothPowerContinuation.resume()
        case .poweredOff:
            self.bluetoothPowerContinuation = nil
            bluetoothPowerContinuation.resume(throwing: AppServiceError.validation("Turn on Bluetooth to set up an Eleph monitor."))
        case .unauthorized:
            self.bluetoothPowerContinuation = nil
            bluetoothPowerContinuation.resume(throwing: AppServiceError.validation("Allow Bluetooth access for Eleph in Settings."))
        case .unsupported:
            self.bluetoothPowerContinuation = nil
            bluetoothPowerContinuation.resume(throwing: AppServiceError.validation("This device does not support Bluetooth setup."))
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = advertisedName ?? peripheral.name ?? "Eleph Monitor"
        let hasSetupService = serviceUUIDs.contains(Self.setupServiceUUID)
        let looksLikeEleph = name.localizedCaseInsensitiveContains("eleph")

        guard hasSetupService || looksLikeEleph else { return }

        discoveredPeripherals[peripheral.identifier] = peripheral

        let setupDevice = SetupDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "Eleph Monitor",
            advertisedName: name,
            signalStrength: RSSI.intValue,
            serviceUUID: hasSetupService ? Self.setupServiceUUID.uuidString : serviceUUIDs.first?.uuidString
        )

        if let index = scanResults.firstIndex(where: { $0.id == setupDevice.id }) {
            scanResults[index] = setupDevice
        } else {
            scanResults.append(setupDevice)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.setupServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let connectContinuation else { return }
        self.connectContinuation = nil
        connectContinuation.resume(
            throwing: AppServiceError.validation(error?.localizedDescription ?? "Could not connect to the Eleph monitor.")
        )
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        setupStatusCharacteristic = nil
        provisioningPayloadCharacteristic = nil
    }
}

extension CoreBluetoothElephSetupService: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: AppServiceError.validation(error.localizedDescription))
            connectContinuation = nil
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.setupServiceUUID }) else {
            connectContinuation?.resume(throwing: AppServiceError.validation("This monitor does not expose the Eleph setup service."))
            connectContinuation = nil
            return
        }

        peripheral.discoverCharacteristics(
            [Self.setupStatusCharacteristicUUID, Self.provisioningPayloadCharacteristicUUID],
            for: service
        )
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectContinuation?.resume(throwing: AppServiceError.validation(error.localizedDescription))
            connectContinuation = nil
            return
        }

        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.setupStatusCharacteristicUUID {
                setupStatusCharacteristic = characteristic
            }
            if characteristic.uuid == Self.provisioningPayloadCharacteristicUUID {
                provisioningPayloadCharacteristic = characteristic
            }
        }

        guard setupStatusCharacteristic != nil, provisioningPayloadCharacteristic != nil else {
            connectContinuation?.resume(throwing: AppServiceError.validation("This monitor is missing required setup characteristics."))
            connectContinuation = nil
            return
        }

        connectContinuation?.resume()
        connectContinuation = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            statusReadContinuation?.resume(throwing: AppServiceError.validation(error.localizedDescription))
            provisioningReadContinuation?.resume(throwing: AppServiceError.validation(error.localizedDescription))
            statusReadContinuation = nil
            provisioningReadContinuation = nil
            return
        }

        if characteristic.uuid == Self.setupStatusCharacteristicUUID {
            if let statusReadContinuation {
                self.statusReadContinuation = nil
                statusReadContinuation.resume(returning: decodeSetupStatus(from: characteristic.value))
                return
            }

            if let provisioningReadContinuation {
                self.provisioningReadContinuation = nil
                provisioningReadContinuation.resume(returning: decodeProvisioningStatus(from: characteristic.value))
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let writeContinuation else { return }
        self.writeContinuation = nil

        if let error {
            writeContinuation.resume(throwing: AppServiceError.validation(error.localizedDescription))
        } else {
            writeContinuation.resume()
        }
    }
}

private extension JSONEncoder {
    static var elephBluetooth: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
