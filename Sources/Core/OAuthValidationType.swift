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

/// Represents the OAuth status codes validation
public enum OAuthValidationType {

    /// Validate OAuth unauthorized code (only 401).
    case basic

    /// Validate only the given status codes.
    case customCodes([Int])
    
    case customValidation((Response?, Error)->Bool)

    /// The list of HTTP status codes to validate.
    var statusCodes: [Int] {
        switch self {
        case .basic:
            return [401]
        case .customCodes(let codes):
            return codes
        case .customValidation:
            return []
        }
    }
}

public protocol OAuthValidatable {
    
    /// The type of OAuth validation to perform on the request. Default is `.basic`.
    var oauthValidationType: OAuthValidationType { get }
}


public extension OAuthValidatable {
    
    /// The type of OAuth validation to perform on the request. Default is `.basic`.
    var oauthValidationType: OAuthValidationType {
        return .basic
    }
    
    
    func failDueToAuthenticationError(_ moyaError: MoyaError)-> Bool {
        switch moyaError {
        case .underlying(let error, let response):
            switch oauthValidationType {
            case .basic, .customCodes:
                if let statusCode = response?.statusCode {
                    let statusCodes = oauthValidationType.statusCodes
                    return statusCodes.contains(statusCode)
                }
                return false
            case .customValidation(let validationClosure):
                return validationClosure(response, error)
            }
        default:
            return false
        }
    }
}
