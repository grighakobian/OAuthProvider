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


public protocol AccessTokenType: Codable {
    
    /// The access token issued by the authorization server.
    var accessToken: String { get }
    
    /// The access token type provides the client with the information
    /// required to successfully utilize the access token to make a protected
    /// resource request (along with type-specific attributes).  The client
    /// MUST NOT use an access token if it does not understand the token
    /// type.
    ///
    /// For example, the "bearer" token type defined in [RFC6750] is utilized
    /// by simply including the access token string in the request:
    ///     GET /resource/1 HTTP/1.1
    ///     Host: example.com
    ///     Authorization: Bearer mF_9.B5f-4.1JqM
    var tokenType: String? { get }
    
    /// If the access token will expire, then it is useful to return a refresh token which applications can use to obtain another access token. However, tokens issued with the implicit grant cannot be issued a refresh token.
    var refreshToken: String? { get }
    
    /// The lifetime in seconds of the access token. For
    /// example, the value "3600" denotes that the access token will
    /// expire in one hour from the time the response was generated.
    /// If omitted, the authorization server SHOULD provide the
    /// expiration time via other means or document the default value.
    var expiresIn: Double? { get }
    
    /// If the scope the user granted is identical to the scope the app requested, this parameter is optional. If the granted scope is different from the requested scope, such as if the user modified the scope, then this parameter is required.
    var scope: String? { get }
}


// MARK: - AccessToken

public struct AccessToken: AccessTokenType {
    public let accessToken: String
    public let tokenType: String?
    public let refreshToken: String?
    public let expiresIn: Double?
    public let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope = "scope"
    }
}
