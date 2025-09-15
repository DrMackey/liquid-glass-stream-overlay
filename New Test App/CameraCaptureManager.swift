//  CameraCaptureManager.swift
//  New Test App
//  Класс для захвата видео с камеры (AVFoundation)
//  Автоматически создано из ContentView.swift

import SwiftUI
import AVFoundation
import Combine
import Foundation

#if os(macOS)
import AppKit
#endif

final class CameraCaptureManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var image: CIImage?
    @Published var errorMessage: String?
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var selectedDeviceID: String?

    private let session = AVCaptureSession()
    lazy var context = CIContext()

    override init() {
        super.init()
        session.sessionPreset = .hd1920x1080
        // Removed setupSession() call here
    }

    func updateAvailableDevices() {
        var allDevices: [AVCaptureDevice] = []
        if #available(macOS 10.15, *) {
            let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .externalUnknown], mediaType: .video, position: .unspecified)
            allDevices = discovery.devices
        } else {
            allDevices = AVCaptureDevice.devices(for: .video)
        }
        availableDevices = allDevices
        if let currentID = selectedDeviceID, !allDevices.contains(where: { $0.uniqueID == currentID }) {
            selectedDeviceID = allDevices.first?.uniqueID
        } else if selectedDeviceID == nil {
            selectedDeviceID = allDevices.first?.uniqueID
        }
    }

    var selectedDevice: AVCaptureDevice? {
        availableDevices.first(where: { $0.uniqueID == selectedDeviceID })
    }

    private func setupSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        guard let device = selectedDevice else {
            let msg = "No video device selected"
            errorMessage = msg
            print(msg)
            return false
        }
        var bestFormat: AVCaptureDevice.Format?
        var bestFrameRateRange: AVFrameRateRange?
        for format in device.formats {
            let desc = format.formatDescription
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            for range in format.videoSupportedFrameRateRanges {
                if dims.width == 1920 && dims.height == 1080 && range.maxFrameRate >= 60 {
                    bestFormat = format
                    bestFrameRateRange = range
                    print("Found suitable format: \(dims.width)x\(dims.height) [\(range.minFrameRate)-\(range.maxFrameRate)] fps")
                    break
                }
            }
            if bestFormat != nil { break }
        }
        if let bestFormat = bestFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat
                device.unlockForConfiguration()
                print("Camera activeFormat set to 1920x1080 at \(bestFrameRateRange?.maxFrameRate ?? 0) fps.")
            } catch {
                let msg = "Could not set FPS/format: \(error)"
                errorMessage = msg
                print(msg)
                return false
            }
        } else {
            let msg = "No suitable 1920x1080@60fps camera format found!"
            errorMessage = msg
            print(msg)
            return false
        }
        guard
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            let msg = "Cannot add input to session"
            errorMessage = msg
            print(msg)
            return false
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "CameraQueue"))
        guard session.canAddOutput(output) else {
            let msg = "Cannot add output to session"
            errorMessage = msg
            print(msg)
            return false
        }
        session.addOutput(output)
        errorMessage = nil
        return true
    }

    func startSession() {
        guard !availableDevices.isEmpty else { return }
        if selectedDeviceID == nil, let first = availableDevices.first {
            selectedDeviceID = first.uniqueID
        }
        stopSession()
        let setupSuccess = setupSession()
        if !setupSuccess {
            errorMessage = errorMessage ?? "Failed to setup session"
            print(errorMessage ?? "Failed to setup session")
        }
        if !session.isRunning && setupSuccess {
            session.startRunning()
        }
    }
    func stopSession() {
        if session.isRunning {
            session.stopRunning()
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        DispatchQueue.main.async { self.image = ciImage }
    }
}
