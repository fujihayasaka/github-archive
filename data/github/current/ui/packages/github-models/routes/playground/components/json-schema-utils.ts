export type JsonSchemaDefinition = {
  name: string
  strict: boolean
  schema: {
    type: 'object'
    properties: {
      /* eslint-disable-next-line @typescript-eslint/no-explicit-any */
      [key: string]: any
    }
    additionalProperties: boolean
    required: string[]
  }
}

const sampleJsonSchema: JsonSchemaDefinition = {
  name: 'describe_animal',
  strict: true,
  schema: {
    type: 'object',
    properties: {
      name: {
        type: 'string',
        description: 'The name of the animal',
      },
      habitat: {
        type: 'string',
        description: 'The habitat the animal lives in',
      },
    },
    additionalProperties: false,
    required: ['name', 'habitat'],
  },
}

export const sampleJsonSchemaString = JSON.stringify(sampleJsonSchema, null, 2)

export function validateJSONSchema(input: string) {
  try {
    return JSON.parse(input)
  } catch {
    return null
  }
}

export const isValidJSONSchema = (input: string): boolean => {
  return validateJSONSchema(input) !== null
}
