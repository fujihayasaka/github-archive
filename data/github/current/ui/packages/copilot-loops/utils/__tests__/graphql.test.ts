import type {GraphQLResult, GraphQLError} from '../graphql'
import {validateGraphQL} from '../graphql'

describe('GraphQL utilities', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('validateGraphQL', () => {
    const requestId = 'test-request-id'

    it('returns true for a valid GraphQL result', () => {
      const result: GraphQLResult = {
        data: {test: 'value'},
      }

      expect(validateGraphQL(result, requestId)).toBe(true)
    })

    it('returns true for a normal response', () => {
      const result: GraphQLResult = {
        data: {test: 'value'},
        timestamp: 123456789,
      }

      expect(validateGraphQL(result, requestId)).toBe(true)
    })

    it('filters out allowed errors', () => {
      const error: GraphQLError = {
        type: 'SAML',
        message: 'SAML error occurred',
        path: ['path', 'to', 'field'],
      }

      const result: GraphQLResult = {
        data: {test: 'value'},
        errors: [error],
        extensions: {},
      }

      expect(validateGraphQL(result, requestId)).toBe(true)
    })

    it('filters out conditional allowed errors', () => {
      const error: GraphQLError = {
        type: 'FORBIDDEN',
        message: 'SAML error',
        path: ['path', 'to', 'field'],
      }

      const result: GraphQLResult = {
        data: {test: 'value'},
        errors: [error],
        extensions: {},
      }

      expect(validateGraphQL(result, requestId)).toBe(true)
    })

    it('throws an error and sends an event for non-allowed errors', () => {
      const error: GraphQLError = {
        type: 'OTHER_ERROR',
        message: 'Something went wrong',
        path: ['path', 'to', 'field'],
      }

      const result: GraphQLResult = {
        data: {test: 'value'},
        errors: [error],
        extensions: {},
      }

      expect(() => validateGraphQL(result, requestId)).toThrow('Something went wrong (path: path,to,field)')
    })

    it('handles errors without path information', () => {
      const error: GraphQLError = {
        type: 'OTHER_ERROR',
        message: 'Something went wrong',
        path: [],
      }

      const result: GraphQLResult = {
        data: {test: 'value'},
        errors: [error],
        extensions: {},
      }

      expect(() => validateGraphQL(result, requestId)).toThrow('Something went wrong')
    })

    it('combines multiple error messages', () => {
      const errors: GraphQLError[] = [
        {
          type: 'ERROR1',
          message: 'First error',
          path: ['path1'],
        },
        {
          type: 'ERROR2',
          message: 'Second error',
          path: ['path2'],
        },
      ]

      const result: GraphQLResult = {
        data: {test: 'value'},
        errors,
        extensions: {},
      }

      expect(() => validateGraphQL(result, requestId)).toThrow('First error (path: path1), Second error (path: path2)')
    })

    it('throws an error when data is missing from the response', () => {
      const result = {
        errors: [],
        extensions: {},
      } as GraphQLResult

      expect(() => validateGraphQL(result, requestId)).toThrow('Failed to fetch data.')
    })
  })
})
