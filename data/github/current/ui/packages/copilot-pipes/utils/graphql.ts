type Json = string | number | boolean | null | {[property: string]: Json} | Json[]

type JsonRoot = {[property: string]: Json}

export type GraphQLError = {type: string; message: string; path: Array<string | number>}

type GraphQLSuccessfulResult = {
  data: JsonRoot
  timestamp?: number
  extensions?: Record<string, Record<string, JsonRoot>>
}

type GraphQLErrorResult = {
  errors: GraphQLError[]
  data?: JsonRoot
  timestamp?: number
  extensions: Record<string, string>
}

export type GraphQLResult = GraphQLSuccessfulResult | GraphQLErrorResult

export function validateGraphQL(decoded: GraphQLResult, requestId: string): decoded is GraphQLSuccessfulResult {
  if ('errors' in decoded && decoded.errors.length) {
    const formatted = decoded.errors
      .map(error => `GraphQL error: ${error.type}: ${error.message} (path: ${error.path})`)
      .join(', ')

    throw new Error(formatted)
  }

  if (!('data' in decoded)) {
    const error = new Error(`Expected data property in response: ${JSON.stringify(decoded)}. requestId: ${requestId}`)
    throw error
  }

  return true
}
