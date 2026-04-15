//
//  main.swift
//  VirtualCam
//
//  Created by Rodney Mackey on 15.04.2026.
//

import Foundation
import CoreMediaIO

let providerSource = VirtualCamProviderSource(clientQueue: nil)
CMIOExtensionProvider.startService(provider: providerSource.provider)

CFRunLoopRun()
