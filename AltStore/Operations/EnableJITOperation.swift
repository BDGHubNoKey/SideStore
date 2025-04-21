//
//  EnableJITOperation.swift
//  EnableJITOperation
//
//  Created by Riley Testut on 9/1/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

import UIKit
import Combine

import AltStoreCore

enum JITEnablementError: Error {
    case invalidURL
    case errorConnecting
    case deviceNotFound
    case other(String)
}

@available(iOS 14, *)
protocol EnableJITContext
{
    var installedApp: InstalledApp? { get }
    
    var error: Error? { get }
}

@available(iOS 14, *)
final class EnableJITOperation<Context: EnableJITContext>: ResultOperation<Void>
{
    let context: Context
    
    private var cancellable: AnyCancellable?
    
    init(context: Context)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        guard let installedApp = self.context.installedApp else {
            return self.finish(.failure(OperationError.invalidParameters("EnableJITOperation.main: self.context.installedApp is nil")))
        }
        
        let userdefaults = UserDefaults.standard
        
        // Check if JIT API URL is configured
        guard let jitAPIURL = userdefaults.string(forKey: "jit_api_base_url") else {
            return self.finish(.failure(OperationError.invalidParameters("JIT API URL not configured. Please set it in Settings.")))
        }
        
        // Set the API base URL if not already set
        JITAPIClient.shared.setBaseURL(jitAPIURL)
        
        // Enable JIT using the API client
        installedApp.managedObjectContext?.perform {
            JITAPIClient.shared.enableJIT(for: installedApp.resignedBundleIdentifier) { result in
                switch result {
                case .success(let message):
                    // Show success notification
                    let content = UNMutableNotificationContent()
                    content.title = "JIT Successfully Enabled"
                    content.subtitle = "JIT Enabled For \(installedApp.name)"
                    content.body = message
                    content.sound = .default
                    
                    let request = UNNotificationRequest(identifier: "EnabledJIT", content: content, trigger: nil)
                    UNUserNotificationCenter.current().add(request)
                    
                    self.finish(.success(()))
                    print("JIT Enabled Successfully via API")
                    
                case .failure(let error):
                    switch error {
                    case .invalidURL:
                        self.finish(.failure(OperationError.invalidParameters("Invalid JIT API URL. Please check your settings.")))
                    case .networkError(let underlyingError):
                        self.finish(.failure(OperationError.networkError(underlyingError)))
                    case .serverError(let message):
                        self.finish(.failure(OperationError.SideJITIssue(error: message)))
                    case .authenticationError:
                        self.finish(.failure(OperationError.authenticationFailed))
                    case .invalidResponse:
                        self.finish(.failure(OperationError.invalidResponse))
                    case .unknown:
                        self.finish(.failure(OperationError.unknown))
                    }
                }
            }
        }
    }
}
