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

public enum OAuthError: String, Error {
    /// The request is missing a required parameter,
    /// includes an invalid parameter value, or is otherwise malformed.
    case invalidRequest = "invalid_request"
    /// The client is not authorized to request an authorization
    /// code using this method.
    case unauthorizedClient = "unauthorized_client"
    /// The authorization server does not support obtaining an
    /// authorization code using this method.
    case unsupportedResponseType = "unsupported_response_type"
    /// The requested scope is invalid, unknown, or malformed.
    case invalidScope = "invalid_scope"
    /// The authorization server encountered an unexpected
    /// condition which prevented it from fulfilling the request.
    case serverError = "server_error"
    /// The authorization server is currently unable to handle
    /// the request due to a temporary overloading or maintenance of the server.
    case temporarilyUnavailable = "temporarily_unavailable"
}
