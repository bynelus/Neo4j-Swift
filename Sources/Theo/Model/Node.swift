import Foundation
import Bolt
import PackStream

public protocol ResponseItem {}

public class Node: ResponseItem {
    public var id: UInt64? = nil

    /// Alias used when generating queries
    public private(set) var modified: Bool = false
    public private(set) var updatedTime: Date = Date()
    public private(set) var createdTime: Date? = nil

    public private(set) var properties: [String: PackProtocol] = [:]
    public private(set) var labels: [String] = []

    private var updatedProperties: [String: PackProtocol] = [:]
    private var removedPropertyKeys = Set<String>()
    private var addedLabels: [String] = []
    private var removedLabels: [String] = []


    public init(
        labels: [String],
        properties: [String: PackProtocol]) {

        self.labels = labels
        self.properties = properties

        self.modified = false
        self.createdTime = Date()
        self.updatedTime = Date()
    }

    init?(data: PackProtocol) {
        if let s = data as? Structure,
            s.signature == 78,
            s.items.count >= 3,
            let nodeId = s.items[0].uintValue(),
            let labelsList = s.items[1] as? List,
            let properties = (s.items[2] as? Map)?.dictionary {
            let labels = labelsList.items.flatMap { $0 as? String }

            self.id = nodeId
            self.labels = labels
            self.properties = properties
            self.modified = false

            self.createdTime = Date()
            self.updatedTime = Date()

        } else {
            return nil
        }
    }

    func add(label: String) {
        self.labels.append(label)
        self.addedLabels.append(label)
        self.removedLabels = self.removedLabels.filter { $0 != label }
    }

    func remove(label: String) {
        self.labels = self.labels.filter { $0 != label }
        self.removedLabels.append(label)
        self.addedLabels = self.addedLabels.filter { $0 != label }
    }

    public func createRequest(withReturnStatement: Bool = true, nodeAlias: String = "node") -> Request {
        let query = createRequestQuery(withReturnStatement: withReturnStatement, nodeAlias: nodeAlias)
        return Request.run(statement: query, parameters: Map(dictionary: self.properties))
    }

    public func createRequestQuery(withReturnStatement: Bool = true, nodeAlias: String = "node", paramSuffix: String = "", withCreate: Bool = true) -> String {
        let labels = self.labels.joined(separator: ":")
        let params = properties.keys.map { "\($0): {\($0)\(paramSuffix)}" }.joined(separator: ", ")

        let query: String
        if withReturnStatement {
            query = "\(withCreate ? "CREATE" : "") (\(nodeAlias):\(labels) { \(params) }) RETURN \(nodeAlias)"
        } else {
            query = "\(withCreate ? "CREATE" : "") (\(nodeAlias):\(labels) { \(params) })"
        }

        return query
    }

    public func updateRequest(withReturnStatement: Bool = true, nodeAlias: String = "node") -> Request {
        let (query, properties) = updateRequestQuery(withReturnStatement: withReturnStatement, nodeAlias: nodeAlias)
        return Request.run(statement: query, parameters: Map(dictionary: properties))
    }

    public func updateRequestQuery(withReturnStatement: Bool = true, nodeAlias: String = "node", paramSuffix: String = "") -> (String, [String:PackProtocol]) {

        guard let id = self.id else {
            print("Error: Cannot create update request for node without id. Did you mean to create it?")
            return ("", [:])
        }

        var properties = [String:PackProtocol]()


        let addedLabels = self.addedLabels.count == 0 ? "" : "\(nodeAlias):" + self.addedLabels.joined(separator: ":")

        let updatedProperties = self.updatedProperties.keys.map { "\(nodeAlias).\($0) = {\($0)\(paramSuffix)}" }.joined(separator: ", ")
        properties.merge( self.updatedProperties.map { key, value in
            return ("\(key)\(paramSuffix)", value)}, uniquingKeysWith: { _, new in return new } )

        var update = [addedLabels, updatedProperties].joined(separator: ", ")
        if update == ", " {
            update = ""
        } else {
            update = "SET \(update)\n"
        }

        let removedProperties = self.removedPropertyKeys.count == 0 ? "" : self.removedPropertyKeys.map { "\(nodeAlias).\($0)" }.joined(separator: ", ")

        let removedLabels = self.removedLabels.count == 0 ? "" : self.removedLabels.map { "\(nodeAlias):\($0)" }.joined(separator: ", ")

        var remove = [ removedLabels, removedProperties ].joined(separator: ", ")
        if remove == ", " {
            remove = ""
        } else {
            remove = "REMOVE \(remove)\n"
        }

        var query: String = "MATCH (\(nodeAlias))\nWHERE id(\(nodeAlias)) = \(id)\n\(update)\(remove)"
        if withReturnStatement {
            query = "\(query)RETURN \(nodeAlias)"
        }

        print(query)

        return (query, properties)
    }

    public func setProperty(key: String, value: PackProtocol?) {
        if let value = value {
            self.properties[key] = value
            self.updatedProperties[key] = value
            self.removedPropertyKeys.remove(key)
        } else {
            self.properties.removeValue(forKey: key)
            self.removedPropertyKeys.insert(key)
        }
        self.modified = true
    }

    public subscript(key: String) -> PackProtocol? {
        get {
            return self.updatedProperties[key] ?? self.properties[key]
        }

        set (newValue) {
            setProperty(key: key, value: newValue)
        }
    }
    
    public func deleteRequest(nodeAlias: String = "node") -> Request {
        let query = deleteRequestQuery(nodeAlias: nodeAlias)
        return Request.run(statement: query, parameters: Map(dictionary: [:]))
    }

    public func deleteRequestQuery(nodeAlias: String = "node") -> String {
        
        guard let id = self.id else {
            print("Error: Cannot create update request for node without id. Did you mean to create it?")
            return ""
        }

        let query = """
                    MATCH (\(nodeAlias)
                    WHERE id(\(nodeAlias) = \(id)
                    DETACH DELETE \(nodeAlias)
                    """

        return query
    }
}

extension Array where Element: Node {

    public func createRequest(withReturnStatement: Bool = true) -> Request {

        var aliases = [String]()
        var queries = [String]()
        var properties = [String: PackProtocol]()
        for i in 0..<self.count {
            let node = self[i]
            let nodeAlias = "node\(i)"
            queries.append(node.createRequestQuery(withReturnStatement: false, nodeAlias: nodeAlias, paramSuffix: "\(i)", withCreate: i == 0))
            aliases.append(nodeAlias)
            for (key, value) in node.properties {
                properties["\(key)\(i)"] = value
            }
        }

        let query: String
        if withReturnStatement {
            query = "\(queries.joined(separator: ", ")) RETURN \(aliases.joined(separator: ","))"
        } else {
            query = queries.joined(separator: ", ")
        }

        return Request.run(statement: query, parameters: Map(dictionary: properties))
    }
    
    public func updateRequest(withReturnStatement: Bool = true) -> Request {
        
        var aliases = [String]()
        var queries = [String]()
        var properties = [String: PackProtocol]()
        for i in 0..<self.count {
            let node = self[i]
            let nodeAlias = "node\(i)"
            let (query, queryProperties) = node.updateRequestQuery(
                withReturnStatement: false,
                nodeAlias: nodeAlias, paramSuffix: "\(i)")
            queries.append(query)
            aliases.append(nodeAlias)
            for (key, value) in queryProperties {
                properties[key] = value
            }
        }
        
        let query: String
        if withReturnStatement {
            query = "\(queries.joined(separator: ", ")) RETURN \(aliases.joined(separator: ","))"
        } else {
            query = queries.joined(separator: ", ")
        }
        
        return Request.run(statement: query, parameters: Map(dictionary: properties))
        
    }
    
    public func deleteRequest(withReturnStatement: Bool = true) -> Request {
        
        let ids = self.flatMap { $0.id }.map { "\($0)" }.joined(separator: ", ")
        let nodeAlias = "node"
        
        let query = """
                    MATCH (\(nodeAlias)
                    WHERE id(\(nodeAlias) IN [\(ids)]
                    DETACH DELETE \(nodeAlias)
                    """
        
        return Request.run(statement: query, parameters: Map(dictionary: [:]))
    }

}
