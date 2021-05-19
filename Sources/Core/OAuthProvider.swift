//    Copyright (c) 2021 Grigor Hakobyan <grighakobian@gmail.com>
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in
//    all copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//    THE SOFTWARE.

import Moya
import Alamofire
#if canImport(UIKit)
import class UIKit.UIApplication
#endif

public protocol OAuthProviderType: AnyObject {
    associatedtype Target: OAuthTargetType
    
    /// Returns wheter the network provider suspended
    var isSuspended: Bool { get }
    /// Suspend network provider to queue new requests
    func suspend()
    /// Resume network provider to start runing pending requests
    func resume()
    /// Cancel all pending queued requests
    func cancelPendingRequests()
    
    /// Designated request-making method. Returns a `Cancellable` token to cancel the request later.
    func request(_ target: Target, callbackQueue: DispatchQueue?, progress: ProgressBlock?, completion: @escaping Completion) -> Cancellable
}

open class OAuthProvider<Target: OAuthTargetType> {
    
    /// Network provider state
    ///
    /// - unauthorized: Unathorized state
    /// - `default`: Default state
    public enum State {
        case unauthorized
        case `default`
    }
    
    /// Thread safe lock
    public let lock: NSRecursiveLock
    
    /// The network provider state
    public var state: State
    
    /// The pending request queue
    public var operationQueue: [Operation]
    
    /// The moya provider for iris API
    public let provider: MoyaProvider<Target>
    
    /// The user credentials store used to check access token is valid or not
    public let accessTokenStore: AccessTokenStore
    
    /// Continue request in background
    public var continueRequestsInBackground: Bool
        
    /// Initialize a OAuth provider
    /// - Parameters:
    ///   - provider: The moya provider
    ///   - accessTokenStore: The access token store
    public init(provider: MoyaProvider<Target>,
                accessTokenStore: AccessTokenStore,
                continueRequestsInBackground: Bool = true) {
        
        self.provider = provider
        self.accessTokenStore = accessTokenStore
        self.continueRequestsInBackground = continueRequestsInBackground
        self.lock = NSRecursiveLock()
        self.state = .default
        self.operationQueue = [Operation]()
    }
    
    open var isSuspended: Bool {
        lock.lock(); defer { lock.unlock() }
        return (state == .unauthorized)
    }
    
    /// Set network provider state `suspended`
    open func suspend() {
        lock.lock()
        state = .unauthorized
        lock.unlock()
    }
    
    /// Resume network provider queued requests
    open func resume() {
        lock.lock()
        state = .default
        while !operationQueue.isEmpty {
            operationQueue.removeFirst().resume()
        }
        lock.unlock()
    }
    
    /// Cancel all queued requests
    open func cancelPendingRequests() {
        lock.lock()
        operationQueue.removeAll()
        state = .default
        lock.unlock()
    }
}

// MARK: - NetworkProviderType

extension OAuthProvider: OAuthProviderType {
    
    @discardableResult
    func requestNormal(_ target: Target,
                       callbackQueue: DispatchQueue? = .none,
                       progress: ProgressBlock? = .none,
                       completion: @escaping Completion) -> Cancellable {
        
        guard continueRequestsInBackground else {
            return provider.request(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
        }
        
        #if canImport(UIKit)
            let identifier = UUID().uuidString
            var backgroundTaskIdentifier: UIBackgroundTaskIdentifier!
            backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: identifier) {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                backgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
            }
        #endif
        
        return provider.request(target, callbackQueue: callbackQueue, progress: progress) { (result) in
            
            #if canImport(UIKit)
                UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                backgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid
            #endif
            
            completion(result)
        }
    }
    
    
    @discardableResult
    public func request(_ target: Target,
                        callbackQueue: DispatchQueue?,
                        progress: ProgressBlock?,
                        completion: @escaping Completion) -> Cancellable {
        
        switch target.authorizationType {
        case .none:
            return requestNormal(target, callbackQueue: callbackQueue, progress: progress) { (result) in
                switch result {
                case .success(let response):
                    self.handleSuccessResponse(response, for: target, completion: completion)
                case .failure:
                    return completion(result)
                }
            }
        default:
            switch state {
            case .unauthorized:
                return queueRequest(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
            default:
                /// Returns `unauthorized` error on performing request
                /// which a needs valid access token
                if (accessTokenStore.getAccessToken() == nil) {
                    cancelPendingRequests()
                    let error = OAuthError.unauthorizedClient
                    completion(.failure(MoyaError.underlying(error, nil)))
                    return EmptyCancellable(isCancelled: true)
                }
                
                return requestNormal(target, callbackQueue: callbackQueue, progress: progress) { (result) in
                    switch result {
                    case .success(let response):
                        self.handleSuccessResponse(response, for: target, completion: completion)
                    case .failure(let moyaError):
                        
                        guard moyaError.isUnauthorized else {
                            return completion(.failure(moyaError))
                        }
                        
                        self.queueRequest(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
                        
                        // Check if refresh token is exists
                        let accessToken = self.accessTokenStore.getAccessToken()
                        guard accessToken?.refreshToken != nil else {
                            return self.setRefreshTokenFailed(with: NSError())
                        }
                        
                        self.refreshToken(completion: completion)
                    }
                }
            }
        }
    }
    
    func handleSuccessResponse(_ response: Response, for target: Target, completion: Completion) {
        do {
            try performAccessTokenStore(target, response: response)
            completion(.success(response))
        } catch {
            completion(.failure(MoyaError.underlying(error, response)))
        }
    }
    
    @inlinable
    func performAccessTokenStore(_ target: Target, response: Response) throws {
        let storeType = target.accessTokenStoreType
        if case .reset = storeType {
            return accessTokenStore.resetAccessToken()
        } else if case .save = storeType {
            let accessToken = try response.map(AccessToken.self)
            return try accessTokenStore.saveAccessToken(accessToken)
        }
    }
    
    @discardableResult
    func queueRequest(_ target: Target, callbackQueue: DispatchQueue?, progress: ProgressBlock?, completion: @escaping Completion) -> Cancellable {
    
        lock.lock(); defer { lock.unlock() }
        
        let cancellableOperation = Operation { [unowned self] () -> Cancellable in
            return self.requestNormal(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
        }
        
        operationQueue.append(cancellableOperation)
        
        return cancellableOperation
    }
    
    func refreshToken(completion: @escaping Completion) {
        lock.lock(); defer { lock.unlock() }
        
        // Check wheter network provider is already suspended to avoid suspending again
        guard self.isSuspended == false else {
            return
        }
        
        // Suspend provider
        self.suspend()
        
        // Notify authentication challange recieve
        self.notify(.didRecieveAuthenticationChallenge)
        self.notify(.didStartAuthenticationChallenge)
        // Perform token refresh request
        
        let refreshTokenTarget = Target.refreshToken
        requestNormal(refreshTokenTarget) { (result) in
            switch result {
            case .success(let response):
                do {
                    try self.performAccessTokenStore(refreshTokenTarget, response: response)
                    // Notify authentication challenge succeed
                    self.notify(.didFinishAuthenticationChallenge)
                    // Resume OAuth provider pending requests
                    self.resume()
                } catch {
                    self.setRefreshTokenFailed(with: error)
                    completion(.failure(MoyaError.underlying(error, response)))
                }
            case .failure(let error):
                self.setRefreshTokenFailed(with: error)
            }
        }
    }
    
    func setRefreshTokenFailed(with error: Error) {
        // Reset user credentials
        accessTokenStore.resetAccessToken()
        // Cancel pending requests
        cancelPendingRequests()
        // Notify authentication challenge failed
        notify(.didFailAuthenticationChallenge, object: error)
    }
    
    /// Creates a notification with a given name and sender and posts it to the notification center.
    /// - Parameters:
    ///   - name: The name of the notification.
    ///   - object: The object posting the notification.
    func notify(_ name: Notification.Name, object: Any? = nil) {
        NotificationCenter.default.post(name: name, object: object)
    }
}
