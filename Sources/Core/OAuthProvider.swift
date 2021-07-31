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

public protocol OAuthProviderType: AnyObject {
    associatedtype Target: OAuthTargetType
    
    /// Designated request-making method. Returns a `Cancellable` token to cancel the request later.
    func request(_ target: Target, callbackQueue: DispatchQueue?, progress: ProgressBlock?, completion: @escaping Completion) -> Cancellable
}

open class OAuthProvider<Target: OAuthTargetType> {
    
    /// Closure that provides the refresh token target for the provider.
    public typealias RefreshTokenClosure = (AccessTokenStore)->Target
    
    /// The moya provider
    public let provider: MoyaProvider<Target>
    
    /// The access token store
    public let accessTokenStore: AccessTokenStore

    /// The operation queue responsible for pending requests execution
    public let operationQueue: OperationQueue
    
    /// A closure that provides the refresh token target for the provider
    public let refreshTokenClosure: RefreshTokenClosure
    
    public private(set) var isRefreshingToken: Bool
    
    let lock = NSLock()
        
    /// Initialize a OAuth provider
    /// - Parameters:
    ///   - provider: The moya provider
    ///   - accessTokenStore: The access token store
    ///   - refreshTokenClosure: The refresh toke closure
    public init(provider: MoyaProvider<Target>,
                accessTokenStore: AccessTokenStore,
                refreshTokenClosure: @escaping RefreshTokenClosure) {
        
        self.provider = provider
        self.accessTokenStore = accessTokenStore
        self.refreshTokenClosure = refreshTokenClosure
        self.operationQueue = OperationQueue()
        self.isRefreshingToken = false
    }
    
    /// A Boolean value indicating whether the provider is suspended.
    public var isSuspended: Bool {
        get { return operationQueue.isSuspended }
        set { operationQueue.isSuspended = newValue }
    }
    
    /// Set network provider state `suspended`
    open func suspend() {
        isSuspended = true
    }
    
    /// Resume network provider queued requests
    open func resume() {
        isSuspended = false
    }
    
    /// Cancel all queued requests
    open func cancelPendingRequests() {
        operationQueue.cancelAllOperations()
    }
}

// MARK: - NetworkProviderType

extension OAuthProvider: OAuthProviderType {
 
    @discardableResult
    func requestNormal(_ target: Target,
                       callbackQueue: DispatchQueue? = .none,
                       progress: ProgressBlock? = .none,
                       completion: @escaping Completion) -> Cancellable {
        
        return provider.request(target,
                                callbackQueue: callbackQueue,
                                progress: progress,
                                completion: completion
        )
    }
    
    @discardableResult
    open func request(_ target: Target,
                        callbackQueue: DispatchQueue? = .none,
                        progress: ProgressBlock? = .none,
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
            if isSuspended {
                return queueRequest(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
            }
            return requestNormal(target, callbackQueue: callbackQueue, progress: progress) { (result) in
                switch result {
                case .success(let response):
                    self.handleSuccessResponse(response, for: target, completion: completion)
                case .failure(let moyaError):
                    guard moyaError.isUnauthrized(for: target) else {
                        return completion(.failure(moyaError))
                    }
                    
                    self.suspend()
                    self.queueRequest(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
                    
                    self.lock.lock(); defer { self.lock.unlock() }
                    
                    if (self.isRefreshingToken == false) {
                        self.isRefreshingToken = true
                        // Check if refresh token is exists
                        let accessToken = self.accessTokenStore.getAccessToken()
                        guard accessToken?.refreshToken != nil else {
                            let error = OAuthError.unauthorizedClient
                            // Reset user credentials
                            self.accessTokenStore.resetAccessToken()
                            self.isRefreshingToken = false
                            // Notify authentication challenge failed
                            return self.notify(.didFailAuthenticationChallenge, object: error)
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
            try accessTokenStore.saveAccessToken(accessToken)
            return resume()
        }
    }
    
    @discardableResult
    func queueRequest(_ target: Target, callbackQueue: DispatchQueue?, progress: ProgressBlock?, completion: @escaping Completion) -> Cancellable {
        let cancellableOperation = CancellableOperation { [unowned self] () -> Cancellable in
            return self.request(target, callbackQueue: callbackQueue, progress: progress, completion: completion)
        }
        operationQueue.addOperation(cancellableOperation)
        return cancellableOperation
    }
    
    func refreshToken(completion: @escaping Completion) {
        // Notify authentication challange recieve
        self.notify(.didRecieveAuthenticationChallenge)
        self.notify(.didStartAuthenticationChallenge)
        // Perform token refresh request
        
        let refreshTokenTarget = refreshTokenClosure(accessTokenStore)
        requestNormal(refreshTokenTarget) { (result) in
            defer { self.isRefreshingToken = false }
            
            switch result {
            case .success(let response):
                do {
                    try self.performAccessTokenStore(refreshTokenTarget, response: response)
                    // Notify authentication challenge succeed
                    self.notify(.didFinishAuthenticationChallenge)
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
