//
//  JITAPIClient.swift
//  SideStore
//
//  Created by Codegen on 2025-04-21.
//  Copyright © 2025 SideStore. All rights reserved.
//

import Foundation
import Combine
import UIKit

enum JITAPIError: Error {
    case invalidURL
    case networkError(Error)
    case serverError(String)
    case authenticationError
    case invalidResponse
    case unknown
}

class JITAPIClient {
    static let shared = JITAPIClient()
    
    private let baseURLKey = "jit_api_base_url"
    private let tokenKey = "jit_api_token"
    
    private var baseURL: URL? {
        if let urlString = UserDefaults.standard.string(forKey: baseURLKey),
           let url = URL(string: urlString) {
            return url
        }
        return nil
    }
    
    private var authToken: String? {
        return KeychainWrapper.standard.string(forKey: tokenKey)
    }
    
    private init() {}
    
    // MARK: - Configuration
    
    func setBaseURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UserDefaults.standard.set(urlString, forKey: baseURLKey)
    }
    
    private func saveToken(_ token: String) {
        KeychainWrapper.standard.set(token, forKey: tokenKey)
    }
    
    // MARK: - API Methods
    
    func registerDevice(completion: @escaping (Result<Void, JITAPIError>) -> Void) {
        guard let baseURL = self.baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        guard let udid = UIDevice.current.identifierForVendor?.uuidString else {
            completion(.failure(.unknown))
            return
        }
        
        let registerURL = baseURL.appendingPathComponent("register")
        
        var request = URLRequest(url: registerURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deviceName = UIDevice.current.name
        let parameters: [String: Any] = [
            "udid": udid,
            "device_name": deviceName
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            completion(.failure(.networkError(error)))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = json["token"] as? String {
                    self?.saveToken(token)
                    completion(.success(()))
                } else {
                    completion(.failure(.invalidResponse))
                }
            } catch {
                completion(.failure(.networkError(error)))
            }
        }
        
        task.resume()
    }
    
    func enableJIT(for bundleID: String, completion: @escaping (Result<String, JITAPIError>) -> Void) {
        guard let baseURL = self.baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        guard let token = self.authToken else {
            // If no token, try to register first
            registerDevice { [weak self] result in
                switch result {
                case .success:
                    self?.enableJIT(for: bundleID, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
            return
        }
        
        let enableJITURL = baseURL.appendingPathComponent("enable-jit")
        
        var request = URLRequest(url: enableJITURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let iosVersion = UIDevice.current.systemVersion
        let parameters: [String: Any] = [
            "bundle_id": bundleID,
            "ios_version": iosVersion
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            completion(.failure(.networkError(error)))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            if httpResponse.statusCode == 401 {
                completion(.failure(.authenticationError))
                return
            }
            
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if httpResponse.statusCode == 200, let message = json["message"] as? String {
                        completion(.success(message))
                    } else if let error = json["error"] as? String {
                        completion(.failure(.serverError(error)))
                    } else {
                        completion(.failure(.invalidResponse))
                    }
                } else {
                    completion(.failure(.invalidResponse))
                }
            } catch {
                completion(.failure(.networkError(error)))
            }
        }
        
        task.resume()
    }
    
    func checkSessionStatus(sessionID: String, completion: @escaping (Result<String, JITAPIError>) -> Void) {
        guard let baseURL = self.baseURL else {
            completion(.failure(.invalidURL))
            return
        }
        
        guard let token = self.authToken else {
            completion(.failure(.authenticationError))
            return
        }
        
        let sessionURL = baseURL.appendingPathComponent("session/\(sessionID)")
        
        var request = URLRequest(url: sessionURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.invalidResponse))
                return
            }
            
            if httpResponse.statusCode == 401 {
                completion(.failure(.authenticationError))
                return
            }
            
            guard let data = data else {
                completion(.failure(.invalidResponse))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    completion(.success(status))
                } else {
                    completion(.failure(.invalidResponse))
                }
            } catch {
                completion(.failure(.networkError(error)))
            }
        }
        
        task.resume()
    }
}

// MARK: - KeychainWrapper

// Simple KeychainWrapper implementation
class KeychainWrapper {
    static let standard = KeychainWrapper()
    
    private init() {}
    
    func set(_ value: String, forKey key: String) {
        if let data = value.data(using: .utf8) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: data
            ]
            
            // Delete any existing item
            SecItemDelete(query as CFDictionary)
            
            // Add the new item
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    
    func string(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess {
            if let data = dataTypeRef as? Data,
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        
        return nil
    }
}
