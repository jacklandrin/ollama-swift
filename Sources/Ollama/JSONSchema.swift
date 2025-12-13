import Foundation

/// A protocol that types can conform to to provide their JSON schema representation.
///
/// Types conforming to this protocol can provide a custom JSON schema
/// that will be used when generating structured outputs.
///
/// **Note:** For many simple types, you don't need to implement this protocol!
/// The `JSONSchemaGenerator` can automatically generate schemas for types where:
/// - All properties are optional (can be decoded from empty JSON `{}`)
/// - The type structure can be inferred via runtime introspection
///
/// **Important:** When using automatic schema generation, all properties are marked as
/// `required` in the JSON schema (even if they're optional in Swift). This ensures the
/// model returns all fields in its response. Your Swift types can still be optional for
/// decoding flexibility.
///
/// You only need to implement `jsonSchema` when:
/// - You want to make some fields truly optional in the JSON schema (not required)
/// - You want to add descriptions, constraints, or other schema metadata
/// - Automatic generation doesn't work for your specific type
///
/// - Example with automatic schema generation (no jsonSchema needed):
/// ```swift
/// struct Country: Codable {
///     let name: String?
///     let capital: String?
///     let languages: [String]?
/// }
///
/// // Schema is automatically generated with all fields marked as required!
/// // This ensures the model returns name, capital, and languages.
/// let (country, _) = try await client.chat(
///     model: "llama3.2",
///     messages: [.user("Tell me about Canada.")],
///     responseType: Country.self
/// )
/// ```
///
/// - Example with custom schema (for required fields):
/// ```swift
/// struct Country: Codable, JSONSchemaRepresentable {
///     let name: String
///     let capital: String
///     let languages: [String]
///     
///     static var jsonSchema: Value {
///         [
///             "type": "object",
///             "properties": [
///                 "name": ["type": "string"],
///                 "capital": ["type": "string"],
///                 "languages": [
///                     "type": "array",
///                     "items": ["type": "string"]
///                 ]
///             ],
///             "required": ["name", "capital", "languages"]
///         ]
///     }
/// }
/// ```
public protocol JSONSchemaRepresentable {
    /// Returns the JSON schema for this type as a `Value`.
    static var jsonSchema: Value { get }
}

/// A utility for generating JSON schemas from Swift Codable types.
public enum JSONSchemaGenerator {
    /// Generates a JSON schema from a Codable type.
    ///
    /// This method first checks if the type conforms to `JSONSchemaRepresentable`
    /// and uses its custom schema. Otherwise, it attempts to automatically generate
    /// a schema by analyzing the type structure using runtime introspection.
    ///
    /// **Automatic schema generation works best when:**
    /// - All properties in your type are optional (can decode from `{}`)
    /// - Your type uses standard Swift types (String, Int, Double, Bool, Array, etc.)
    ///
    /// For types with required properties, consider implementing `JSONSchemaRepresentable`
    /// to provide a custom schema with proper `required` fields.
    ///
    /// - Parameter type: The Codable type to generate a schema for
    /// - Returns: A JSON schema as a `Value` object
    /// - Throws: An error if the schema cannot be generated
    public static func schema<T: Codable>(for type: T.Type) throws -> Value {
        // If the type conforms to JSONSchemaRepresentable, use its custom schema
        if let representable = type as? any JSONSchemaRepresentable.Type {
            return representable.jsonSchema
        }
        
        // Otherwise, generate schema from Codable introspection
        return try generateSchema(for: type)
    }
    
    private static func generateSchema<T: Codable>(for type: T.Type) throws -> Value {
        // For primitive types, return their schema directly
        if let primitiveSchema = primitiveSchema(for: type) {
            return primitiveSchema
        }
        
        // For arrays, try to generate schema for the element type
        if let arrayType = type as? any ArrayTypeProtocol.Type {
            // Try to generate schema for array of the element type
            // We'll use a helper that works with Any.Type
            let elementSchema = try schemaForAnyType(arrayType.elementType)
            return [
                "type": "array",
                "items": elementSchema
            ]
        }
        
        // For optionals, generate schema for the wrapped type
        if let optionalType = type as? any OptionalTypeProtocol.Type {
            // Generate schema for the wrapped type
            let wrappedSchema = try schemaForAnyType(optionalType.wrappedType)
            return wrappedSchema
        }
        
        // For complex types (structs, classes), we need to use a sample instance
        // This requires the type to be initializable or have a way to create a sample
        return try objectSchema(for: type)
    }
    
    // Helper function to generate schema from Any.Type
    // This allows us to handle arrays and optionals recursively
    private static func schemaForAnyType(_ anyType: Any.Type) throws -> Value {
        // Check for JSONSchemaRepresentable first
        if let representable = anyType as? any JSONSchemaRepresentable.Type {
            return representable.jsonSchema
        }
        
        // Handle primitive types
        if anyType == String.self {
            return ["type": "string"]
        } else if anyType == Int.self || anyType == Int8.self || anyType == Int16.self ||
                  anyType == Int32.self || anyType == Int64.self ||
                  anyType == UInt.self || anyType == UInt8.self || anyType == UInt16.self ||
                  anyType == UInt32.self || anyType == UInt64.self {
            return ["type": "integer"]
        } else if anyType == Double.self || anyType == Float.self {
            return ["type": "number"]
        } else if anyType == Bool.self {
            return ["type": "boolean"]
        }
        
        // For arrays, recurse
        if let arrayType = anyType as? any ArrayTypeProtocol.Type {
            let elementSchema = try schemaForAnyType(arrayType.elementType)
            return [
                "type": "array",
                "items": elementSchema
            ]
        }
        
        // For optionals, recurse
        if let optionalType = anyType as? any OptionalTypeProtocol.Type {
            return try schemaForAnyType(optionalType.wrappedType)
        }
        
        // Default to object for complex types
        // Users should provide custom schemas via JSONSchemaRepresentable for best results
        return [
            "type": "object",
            "properties": [:],
            "required": []
        ]
    }
    
    private static func primitiveSchema<T>(for type: T.Type) -> Value? {
        if type == String.self {
            return ["type": "string"]
        } else if type == Int.self || type == Int8.self || type == Int16.self || 
                  type == Int32.self || type == Int64.self || 
                  type == UInt.self || type == UInt8.self || type == UInt16.self ||
                  type == UInt32.self || type == UInt64.self {
            return ["type": "integer"]
        } else if type == Double.self || type == Float.self {
            return ["type": "number"]
        } else if type == Bool.self {
            return ["type": "boolean"]
        }
        return nil
    }
    
    private static func objectSchema<T: Codable>(for type: T.Type) throws -> Value {
        // Use Mirror to introspect the type structure
        // This allows us to automatically generate schemas without manual definition
        return try mirrorBasedSchema(for: type)
    }
    
    private static func mirrorBasedSchema<T: Codable>(for type: T.Type) throws -> Value {
        // Try to create a sample instance to inspect
        // We'll attempt multiple strategies to create an instance
        
        // Strategy 1: Try to decode from empty JSON (works if all fields are optional)
        let emptyJSON = "{}".data(using: .utf8)!
        let decoder = JSONDecoder()
        
        if let instance = try? decoder.decode(type, from: emptyJSON) {
            // All fields are optional, but we can still inspect the structure
            return try schemaFromInstance(instance)
        }
        
        // Strategy 2: Try to create an instance with default values
        if let instance = try? createInstanceWithDefaults(type) {
            return try schemaFromInstance(instance)
        }
        
        // Strategy 3: Fallback - return generic schema
        // Users can provide custom schema via JSONSchemaRepresentable for best results
        return try schemaFromTypeMetadata(type)
    }
    
    private static func createInstanceWithDefaults<T: Codable>(_ type: T.Type) throws -> T? {
        // Try to create an instance by encoding a JSON with default values
        // This works for types that can handle missing or default values
        
        // Strategy: Create a JSON with null/default values and try to decode
        // This is limited but works for some cases
        
        // For structs with default initializers, we could try that
        // But Swift doesn't provide a way to check for default init at runtime
        
        // Alternative: Try decoding with a JSON that has null for all possible keys
        // This requires knowing the keys, which we don't have without an instance
        
        // For now, this is a placeholder
        // The best automatic generation works when:
        // 1. All properties are optional (can decode from {})
        // 2. Type provides custom schema via JSONSchemaRepresentable
        // 3. Type has a default initializer (we'd need Swift macros to detect this)
        
        return nil
    }
    
    private static func schemaFromInstance<T: Codable>(_ instance: T) throws -> Value {
        let mirror = Mirror(reflecting: instance)
        var properties: [String: Value] = [:]
        var required: [String] = []
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove the underscore prefix that Swift adds to property names
            let propertyName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            
            // Determine the type and whether it's optional
            let valueType = type(of: child.value)
            let isOptional = valueType is any OptionalTypeProtocol.Type
            
            // Generate schema for the property type
            let propertySchema: Value
            if isOptional {
                // For optionals, get the wrapped type
                if let optionalType = valueType as? any OptionalTypeProtocol.Type {
                    propertySchema = try schemaForAnyType(optionalType.wrappedType)
                } else {
                    propertySchema = ["type": "object"]
                }
            } else {
                propertySchema = try schemaForAnyType(valueType)
            }
            
            properties[propertyName] = propertySchema
            
            // Always add to required array, even if optional in Swift
            // This ensures the model returns all fields in the response
            // The Swift type can still be optional for decoding flexibility
            required.append(propertyName)
        }
        
        return [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map { .string($0) })
        ]
    }
    
    private static func schemaFromTypeMetadata<T: Codable>(_ type: T.Type) throws -> Value {
        // For types we can't instantiate, try to use Mirror on the type itself
        // This is more limited but can still provide some information
        
        // Try to create a minimal instance by attempting to decode with various strategies
        // If that fails, return a generic object schema
        
        // Attempt to get type information through encoding a dummy value
        // This is a fallback - the best approach is to have an instance
        
        // For now, return a generic schema with a note that custom schema is recommended
        // In practice, users should either:
        // 1. Provide a custom schema via JSONSchemaRepresentable
        // 2. Ensure their type can be decoded from empty JSON (all optionals)
        // 3. Use a type that we can inspect via Mirror
        
        return [
            "type": "object",
            "properties": [:],
            "required": []
        ]
    }
}

// MARK: - Type Introspection Helpers

private protocol ArrayTypeProtocol {
    static var elementType: Any.Type { get }
}

extension Array: ArrayTypeProtocol {
    static var elementType: Any.Type {
        Element.self
    }
}

private protocol OptionalTypeProtocol {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalTypeProtocol {
    static var wrappedType: Any.Type {
        Wrapped.self
    }
}

// MARK: - Convenience Extensions

extension JSONSchemaGenerator {
    /// Generates a JSON schema from a Codable type instance.
    ///
    /// - Parameter instance: An instance of the Codable type
    /// - Returns: A JSON schema as a `Value` object
    /// - Throws: An error if the schema cannot be generated
    public static func schema<T: Codable>(from instance: T) throws -> Value {
        return try schema(for: type(of: instance))
    }
}

