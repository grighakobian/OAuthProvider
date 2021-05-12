//
//  Notification.Name.swift
//  OAuthProvider
//
//  Created by Grigor Hakobyan on 06.05.21.
//

import Foundation

extension Notification.Name {
    
    static let didRecieveAuthenticationChallenge = Notification.Name("didRecieveAuthenticationChallenge")
    
    static let didStartAuthenticationChallenge = Notification.Name("didStartAuthenticationChallenge")
    
    static let didFinishAuthenticationChallenge = Notification.Name("didFinishAuthenticationChallenge")
    
    static let didFailAuthenticationChallenge = Notification.Name("didFailAuthenticationChallenge")
}
