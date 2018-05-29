import NIO

internal final class _Cursor {
    var id: Int64
    var initialBatch: [Document]?
    var drained: Bool {
        return self.id == 0
    }
    let collection: Collection
    
    init(reply: CursorReply, in collection: Collection) {
        self.id = reply.cursor.id
        self.initialBatch = reply.cursor.firstBatch
        self.collection = collection
    }
    
    /// Performs a `GetMore` command on the database, requesting the next batch of items
    func getMore(batchSize: Int) -> EventLoopFuture<CursorBatch<Document>> {
        if let initialBatch = self.initialBatch {
            self.initialBatch = nil
            return collection.eventLoop.newSucceededFuture(result: CursorBatch(batch: initialBatch, isLast: self.drained))
        }
        
        guard !drained else {
            return collection.eventLoop.newFailedFuture(error: MongoKittenError(.cannotGetMore, reason: .cursorDrained))
        }
        
        let command = GetMore(cursorId: self.id, batchSize: batchSize, on: collection)
        return collection.connection.execute(command: command).map { newCursor in
            self.id = newCursor.cursor.id
            
            return CursorBatch(batch: newCursor.cursor.nextBatch, isLast: self.drained)
        }
    }
}

public struct CursorBatch<Element> {
    typealias Transform = (Document) throws -> Element
    
    internal let isLast: Bool
    internal let batch: [Document]
    internal let batchSize: Int
    internal var currentItem = 0
    let transform: Transform
    
    internal init(batch: [Document], isLast: Bool, transform: @escaping Transform) {
        self.batch = batch
        self.isLast = isLast
        self.transform = transform
        self.batchSize = batch.count
    }
    
    private init<E>(base: CursorBatch<E>, transform: @escaping (E) throws -> Element) {
        self.batch = base.batch
        self.isLast = base.isLast
        self.batchSize = base.batchSize
        self.currentItem = base.currentItem
        self.transform = { try transform(base.transform($0)) }
    }
    
    mutating func nextElement() throws -> Element? {
        guard currentItem < batchSize else {
            return nil
        }
        
        let element = try transform(batch[currentItem])
        currentItem = currentItem &+ 1
        return element
    }
    
    func map<T>(_ transform: @escaping (Element) throws -> T) -> CursorBatch<T> {
        return CursorBatch<T>(base: self, transform: transform)
    }
}

fileprivate extension CursorBatch where Element == Document {
    init(batch: [Document], isLast: Bool) {
        self.init(batch: batch, isLast: isLast) { $0 }
    }
}

public protocol Cursor {
    associatedtype Element
    var collection: Collection { get }
    
    var batchSize: Int { get }
    func setBatchSize(_ batchSize: Int) -> Self
    
    func execute() -> EventLoopFuture<FinalizedCursor<Self>>
    
    func transformElement(_ element: Document) throws -> Element
    
    @discardableResult
    func forEach(handler: @escaping (Element) throws -> Void) -> EventLoopFuture<Void>
    
    func map<E>(transform: @escaping (Element) throws -> E) -> MappedCursor<Self, E>
    func flatMap<E>(transform: @escaping (Element) throws -> EventLoopFuture<E>) -> FlatMappedCursor<Self, E>
}

internal protocol CursorBasedOnOtherCursor : Cursor {
    associatedtype Base : Cursor
    
    var underlyingCursor: Base { get }
}

extension CursorBasedOnOtherCursor {
    public func setBatchSize(_ batchSize: Int) -> Self {
        _ = underlyingCursor.setBatchSize(batchSize)
        return self
    }
    
    public var batchSize: Int {
        return underlyingCursor.batchSize
    }
    
    public var collection: Collection {
        return underlyingCursor.collection
    }
    
    public func execute() -> EventLoopFuture<FinalizedCursor<Self>> {
        return self.underlyingCursor.execute().map { result in
            return FinalizedCursor(basedOn: self, cursor: result.cursor)
        }
    }
}

public final class FinalizedCursor<Base: Cursor> {
    let base: Base
    let cursor: _Cursor
    
    init(basedOn base: Base, cursor: _Cursor) {
        self.base = base
        self.cursor = cursor
    }
    
    /// - returns: A future resolving with the next element, or with `nil` if the cursor is drained
//    func next() -> EventLoopFuture<Element?>
    
    internal func nextBatch() -> EventLoopFuture<CursorBatch<Base.Element>> {
        return cursor.getMore(batchSize: base.batchSize).thenThrowing { batch in
            return batch.map(self.base.transformElement)
        }
    }
}

extension Cursor where Element == Document {
    public func decode<D: Decodable>(to type: D.Type, using decoder: BSONDecoder = BSONDecoder()) throws -> MappedCursor<Self, D> {
        return self.map { document in
            return try decoder.decode(D.self, from: document)
        }
    }
}

extension Cursor {
    @discardableResult
    public func forEach(handler: @escaping (Element) throws -> Void) -> EventLoopFuture<Void> {
        return execute().then { finalizedCursor in
            func nextBatch() -> EventLoopFuture<Void> {
                return finalizedCursor.nextBatch().then { batch in
                    do {
                        var batch = batch
                        
                        while let element = try batch.nextElement() {
                            try handler(element)
                        }
                        
                        if batch.isLast {
                            return self.collection.connection.eventLoop.newSucceededFuture(result: ())
                        }
                        
                        return nextBatch()
                    } catch {
                        return self.collection.connection.eventLoop.newFailedFuture(error: error)
                    }
                }
            }
            
            return nextBatch()
        }
    }
    
    public func map<E>(transform: @escaping (Element) throws -> E) -> MappedCursor<Self, E> {
        return MappedCursor(underlyingCursor: self, transform: transform)
    }
    
    public func flatMap<E>(transform: @escaping (Element) throws -> EventLoopFuture<E>) -> FlatMappedCursor<Self, E> {
        unimplemented()
    }
}

public final class FlatMappedCursor<Base: Cursor, Element> : CursorBasedOnOtherCursor {
    
    internal typealias Transform<E> = (Base.Element) throws -> EventLoopFuture<E>
    
    var underlyingCursor: Base
    
    internal init(underlyingCursor cursor: Base, transform: @escaping Transform<Element>) {
        unimplemented()
    }
    
    public func transformElement(_ element: Document) throws -> Element {
        unimplemented()
    }
}
    
public final class MappedCursor<Base: Cursor, Element> : CursorBasedOnOtherCursor {
    internal typealias Transform<E> = (Base.Element) throws -> E
    
    internal var underlyingCursor: Base
    var transform: Transform<Element>
    
    internal init(underlyingCursor cursor: Base, transform: @escaping Transform<Element>) {
        self.underlyingCursor = cursor
        self.transform = transform
    }
    
    public func transformElement(_ element: Document) throws -> Element {
        let input = try underlyingCursor.transformElement(element)
        return try transform(input)
    }
}

public final class FindCursor: Cursor {
    public typealias Element = Document
    
    public var batchSize = 101
    public let collection: Collection
    private var operation: FindOperation
    public private(set) var didExecute = false
    
    public init(operation: FindOperation, on collection: Collection) {
        self.operation = operation
        self.collection = collection
    }
    
    public func execute() -> EventLoopFuture<FinalizedCursor<FindCursor>> {
        return self.collection.connection.execute(command: self.operation).mapToResult(for: collection).map { cursor in
            return FinalizedCursor(basedOn: self, cursor: cursor)
        }
    }
    
    public func setBatchSize(_ batchSize: Int) -> FindCursor {
        self.batchSize = batchSize
        return self
    }
    
    public func transformElement(_ element: Document) throws -> Document {
        return element
    }
}
