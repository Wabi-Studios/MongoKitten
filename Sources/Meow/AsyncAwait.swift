#if compiler(>=5.5)
import _NIOConcurrency
import NIO
import MongoClient
import MongoKitten

@available(macOS 12, iOS 15, *)
extension MeowDatabase {
    public struct Async {
        public let nio: MeowDatabase
        
        init(nio: MeowDatabase) {
            self.nio = nio
        }
        
        public var name: String { nio.raw.name }
        
        public func collection<M: BaseModel>(for model: M.Type) -> MeowCollection<M>.Async {
            return MeowCollection<M>(database: nio, named: M.collectionName).async
        }
        
        public subscript<M: BaseModel>(type: M.Type) -> MeowCollection<M>.Async {
            return collection(for: type)
        }
    }
    
    public var `async`: Async {
        Async(nio: self)
    }
}

@available(macOS 12, iOS 15, *)
extension MeowCollection {
    public struct Async {
        public let nio: MeowCollection<M>
        
        init(nio: MeowCollection<M>) {
            self.nio = nio
        }
    }
    
    public var `async`: Async {
        Async(nio: self)
    }
}

@available(macOS 12, iOS 15, *)
extension MeowCollection.Async where M: ReadableModel {
    public func find(where filter: Document = [:]) -> MappedCursor<FindQueryBuilder, M> {
        return nio.find(where: filter)
    }
    
    public func find<Q: MongoKittenQuery>(where filter: Q) -> MappedCursor<FindQueryBuilder, M> {
        return self.find(where: filter.makeDocument())
    }
    
    public func findOne(where filter: Document) async throws -> M? {
        return try await nio.findOne(where: filter).get()
    }
    
    public func findOne<Q: MongoKittenQuery>(where filter: Q) async throws -> M? {
        return try await nio.findOne(where: filter).get()
    }
    
    public func count(where filter: Document) async throws -> Int {
        return try await nio.count(where: filter).get()
    }
    
    public func count<Q: MongoKittenQuery>(where filter: Q) async throws -> Int {
        return try await self.count(where: filter.makeDocument())
    }
    
    public func watch(options: ChangeStreamOptions = .init()) async throws -> ChangeStream<M> {
        return try await nio.watch(options: options).get()
    }
    
    public func buildChangeStream(options: ChangeStreamOptions = .init(), @AggregateBuilder build: () -> AggregateBuilderStage) async throws -> ChangeStream<M> {
        return try await nio.buildChangeStream(options: options, build: build).get()
    }
}

@available(macOS 12, iOS 15, *)
extension MeowCollection.Async where M: MutableModel {
    @discardableResult
    public func insert(_ instance: M) async throws -> InsertReply {
        return try await nio.insert(instance).get()
    }
    
    @discardableResult
    public func insertMany(_ instances: [M]) async throws -> InsertReply {
        return try await nio.insertMany(instances).get()
    }
    
    @discardableResult
    public func upsert(_ instance: M) async throws -> UpdateReply {
        return try await nio.upsert(instance).get()
    }
    
    @discardableResult
    public func deleteOne(where filter: Document) async throws -> DeleteReply {
        return try await nio.deleteOne(where: filter).get()
    }
    
    @discardableResult
    public func deleteOne<Q: MongoKittenQuery>(where filter: Q) async throws -> DeleteReply {
        return try await nio.deleteOne(where: filter).get()
    }
    
    @discardableResult
    public func deleteAll(where filter: Document) async throws -> DeleteReply {
        return try await nio.deleteAll(where: filter).get()
    }
    
    @discardableResult
    public func deleteAll<Q: MongoKittenQuery>(where filter: Q) async throws -> DeleteReply {
        return try await nio.deleteAll(where: filter).get()
    }
    
    //    public func saveChanges(_ changes: PartialChange<M>) -> EventLoopFuture<UpdateReply> {
    //        return raw.updateOne(where: "_id" == changes.entity, to: [
    //            "$set": changes.changedFields,
    //            "$unset": changes.removedFields
    //        ])
    //    }
}

@available(macOS 12, iOS 15, *)
extension Reference {
    /// Resolves a reference
    public func resolve(in context: MeowDatabase, where query: Document = Document()) async throws -> M {
        try await resolve(in: context, where: query).get()
    }
    
    /// Resolves a reference, returning `nil` if the referenced object cannot be found
    public func resolveIfPresent(in context: MeowDatabase, where query: Document = Document()) async throws -> M? {
        try await resolveIfPresent(in: context, where: query).get()
    }
    
    public func exists(in db: MeowDatabase) async throws -> Bool {
        return try await exists(in: db).get()
    }
    
    public func exists(in db: MeowDatabase, where filter: Document) async throws -> Bool {
        return try await exists(in: db, where: filter).get()
    }
    
    public func exists<Query: MongoKittenQuery>(in db: MeowDatabase, where filter: Query) async throws -> Bool {
        return try await exists(in: db, where: filter).get()
    }
}
    
@available(macOS 12, iOS 15, *)
extension Reference where M: MutableModel {
    @discardableResult
    public func deleteTarget(in context: MeowDatabase) async throws -> MeowOperationResult {
        try await deleteTarget(in: context).get()
    }
}
#endif
