import {type ZodTypeAny, ZodObject, type ZodArray} from 'zod'

/** JSON Schema type definitions */
type JSONSchema = JSONSchemaString | JSONSchemaNumber | JSONSchemaBoolean | JSONSchemaArray | JSONSchemaObject

interface JSONSchemaString {
  type: 'string'
  enum?: string[]
}

interface JSONSchemaNumber {
  type: 'number'
}

interface JSONSchemaBoolean {
  type: 'boolean'
}

interface JSONSchemaArray {
  type: 'array'
  items: JSONSchema
}

interface JSONSchemaObject {
  type: 'object'
  properties: {[key: string]: JSONSchema}
  required?: string[]
}

/**
 * Converts a Zod schema to a JSON Schema.
 *
 * @param schema - A Zod schema.
 * @returns The corresponding JSON Schema.
 */
export function zodTypeToJSONSchema<T extends ZodTypeAny>(schema: T): JSONSchema {
  const def = schema._def

  switch (def.typeName) {
    case 'ZodString': {
      return {type: 'string'}
    }

    case 'ZodNumber': {
      return {type: 'number'}
    }

    case 'ZodBoolean': {
      return {type: 'boolean'}
    }

    case 'ZodArray': {
      // Using type narrowing with instanceof
      const arraySchema = schema as unknown as ZodArray<ZodTypeAny>
      return {
        type: 'array',
        items: zodTypeToJSONSchema(arraySchema._def.type),
      }
    }

    case 'ZodObject': {
      // Use instanceof to narrow the type to ZodObject
      if (schema instanceof ZodObject) {
        // `shape` is a mapping from keys to Zod schemas.
        const shape = schema.shape
        const properties: {[key: string]: JSONSchema} = {}
        const required: string[] = []

        // Iterate over each key in the shape.
        for (const key in shape) {
          const propSchema = shape[key]
          properties[key] = zodTypeToJSONSchema(propSchema)
          if (!isOptional(propSchema)) {
            required.push(key)
          }
        }

        // Only include required if there are any entries.
        return {
          type: 'object',
          properties,
          ...(required.length > 0 ? {required} : {}),
        }
      }
      throw new Error('Encountered an object schema that is not an instance of ZodObject')
    }

    case 'ZodEnum': {
      return {
        type: 'string',
        enum: def.values,
      }
    }

    default:
      throw new Error(`Unsupported Zod type: ${def.typeName}`)
  }
}

/**
 * Checks whether a given Zod schema is marked as optional.
 *
 * @param schema - The Zod schema to check.
 * @returns True if the schema is optional; false otherwise.
 */
function isOptional(schema: ZodTypeAny): boolean {
  return schema._def.typeName === 'ZodOptional'
}
