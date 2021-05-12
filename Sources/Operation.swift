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

public protocol OperationType: Cancellable {
    func resume()
}

public class Operation: OperationType {
    
    private var _isCancelled: Bool = false
    private var innerCancellable: Cancellable?
    
    let operation: ()->Cancellable
    
    init(_ operation: @escaping ()->Cancellable) {
        self.operation = operation
    }
    
    public func resume() {
        if _isCancelled {
            return
        }
        innerCancellable = operation()
    }
    
    // MARK: Cancellable
    
    public var isCancelled: Bool {
        return _isCancelled
    }
    
    public func cancel() {
        _isCancelled = true
        innerCancellable?.cancel()
    }
}


class EmptyCancellable: Cancellable {
    var isCancelled: Bool
    
    init(isCancelled: Bool) {
        self.isCancelled = isCancelled
    }
    
    func cancel() {
        isCancelled = true
    }
}
