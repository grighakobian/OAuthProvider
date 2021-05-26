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
    
    /// Returns wheter the OAuth provider authenticated
    var authenticationState: AuthenticationState { get }
    
    /// Suspend OAuth provider to queue new requests
    func suspend()
    
    /// Resume OAuth provider to start runing pending requests
    func resume()
    
    /// Cancel all pending requests
    func cancelPendingRequests()
    
    /// Designated request-making method. Returns a `Cancellable` token to cancel the request later.
    func request(_ target: Target, callbackQueue: DispatchQueue?, progress: ProgressBlock?, completion: @escaping Completion) -> Cancellable
}

open class OAuthProvider<Target: OAuthTargetType> {
    
    /// Closure that provides the refresh token target for the provider.
    public typealias RefreshTokenClosure = ()->Target
    
    /// Thread safe lock
    public let lock: NSRecursiveLock
    
    /// The  provider authentication state
    public var authenticationState: AuthenticationState
    
    /// The operation queue responsible for pending requests execution
    public let operationQueue: OperationQueue
    
    /// The moya provider
    public let provider: MoyaProvider<Target>
    
    /// The access token store
    public let accessTokenStore: AccessTokenStore
    
    /// A closure that provides the refresh token target for the provider
    public let refreshTokenClosure: RefreshTokenClosure
    
    /// Continue request in background
    public var continueRequestsInBackground: Bool
        
    /// Initialize a OAuth provider
    /// - Parameters:
    ///   - provider: The moya provider
    ///   - accessTokenStore: The access token store
    ///   - refreshTokenClosure: The refresh toke closure
    ///   - continueRequestsInBackground: Continue requests in background: default`true`
    public init(provider: MoyaProvider<Target>,
                accessTokenStore: AccessTokenStore,
                refreshTokenClosure: @escaping RefreshTokenClosure,
                continueRequestsInBackground: Bool = true) {
        
        self.provider = provider
        self.accessTokenStore = accessTokenStore
        self.refreshTokenClosure = refreshTokenClosure
        self.continueRequestsInBackground = continueRequestsInBackground
        self.lock = NSRecursiveLock()
        self.authenticationState = .authorized
        
        self.operationQueue = OperationQueue()
        self.operationQueue.underlyingQueue = DispatchQueue.global(qos: .userInteractive)
        self.operationQueue.isSuspended = true
    }
    
    open var isAuthenticated: Bool {
        lock.lock(); defer { lock.unlock() }
        return (authenticationState.isAuthorized)
    }
    
    /// Set network provider state `suspended`
    open func suspend() {
        lock.lock()
        authenticationState = .unauthorized
        operationQueue.isSuspended = true
        lock.unlock()
    }
    
    /// Resume network provider queued requests
    open func resume() {
        lock.lock()
        authenticationState = .authorized
        operationQueue.isSuspended = false
        lock.unlock()
    }
    
    /// Cancel all queued requests
    open func cancelPendingRequests() {
        lock.lock()
        authenticationState = .authorized
        operationQueue.cancelAllOperations()
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
            switch authenticationState {
            case .unauthorized:
                return queueRequest(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
            default:
                /// Returns `unauthorized` error on performing request
                /// which a needs valid access token
                if (accessTokenStore.getAccessToken() == nil) {
                    cancelPendingRequests()
                    let error = OAuthError.unauthorizedClient
                    completion(.failure(MoyaError.underlying(error, nil)))
                    return Operation()
                }
                
                return requestNormal(target, callbackQueue: callbackQueue, progress: progress) { (result) in
                    switch result {
                    case .success(let response):
                        self.handleSuccessResponse(response, for: target, completion: completion)
                    case .failure(let moyaError):
                        guard moyaError.isUnauthrized(for: target) else {
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
        
        let cancellableOperation = CancellableOperation { [unowned self] () -> Cancellable in
            return self.requestNormal(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
        }
        operationQueue.addOperation(cancellableOperation)
        return cancellableOperation
    }
    
    func refreshToken(completion: @escaping Completion) {
        lock.lock(); defer { lock.unlock() }
        
        // Check wheter network provider is already suspended to avoid suspending again
        guard self.isAuthenticated == false else {
            return
        }
        
        // Suspend provider
        self.suspend()
        
        // Notify authentication challange recieve
        self.notify(.didRecieveAuthenticationChallenge)
        self.notify(.didStartAuthenticationChallenge)
        // Perform token refresh request
        
        let refreshTokenTarget = refreshTokenClosure()
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
            case .failure(let moyaError):
                if moyaError.isUnauthrized(for: refreshTokenTarget)  {
                    self.setRefreshTokenFailed(with: moyaError)
                }
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
