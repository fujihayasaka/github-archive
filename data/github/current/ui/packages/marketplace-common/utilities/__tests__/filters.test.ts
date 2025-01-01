import {
  filterStringFromQuery,
  getValidFilterValueFromParsedQuery,
  queryFromFilterString,
  removeFilterFromQuery,
} from '../filters'

describe('filters', () => {
  describe('filterStringFromQuery', () => {
    it('should return type:{type} if type is found', () => {
      expect(filterStringFromQuery('apps', null, null, null)).toBe('type:apps ')
    })

    it('should return type:copilot if copilotApp is found', () => {
      expect(filterStringFromQuery(null, 'true', null, null)).toBe('type:copilot ')
    })

    it('should return empty string if neither type nor copilotApp is found', () => {
      expect(filterStringFromQuery(null, null, null, null)).toBe('')
    })

    it('should append the query if found', () => {
      expect(filterStringFromQuery('apps', null, 'search', null)).toBe('type:apps search')
    })

    it('should handle category if provided', () => {
      expect(filterStringFromQuery('apps', null, 'search', 'utilities')).toBe('type:apps category:utilities search')
    })

    it('should handle edge case with both type and copilotApp', () => {
      expect(filterStringFromQuery('actions', 'true', 'search', null)).toBe('type:copilot search')
    })

    it('should return space after filters if no query', () => {
      expect(filterStringFromQuery('apps', null, null, null)).toBe('type:apps ')
    })

    it('should return space after multiple filters if no query', () => {
      expect(filterStringFromQuery('apps', null, null, 'utilities')).toBe('type:apps category:utilities ')
    })

    it('should return space after filters if query is filter', () => {
      expect(filterStringFromQuery('models', null, 'publisher:GitHub', null)).toBe('type:models publisher:GitHub ')
    })

    it('should return space after filters if filter last chunk of query', () => {
      expect(filterStringFromQuery('models', null, 'search publisher:GitHub', null)).toBe(
        'type:models search publisher:GitHub ',
      )
    })

    it('should not add extra space for empty search', () => {
      expect(filterStringFromQuery(null, null, null, null)).toBe('')
    })

    it('should not add space if query is not a filter', () => {
      expect(filterStringFromQuery(null, null, 'search', null)).toBe('search')
    })
  })

  describe('queryFromFilterString', () => {
    it('should parse type from filter string', () => {
      expect(queryFromFilterString('type:apps')).toEqual({
        type: 'apps',
        copilotApp: null,
        query: '',
        category: null,
      })
    })

    it('should parse copilotApp from filter string', () => {
      expect(queryFromFilterString('type:copilot')).toEqual({
        type: 'apps',
        copilotApp: 'true',
        query: '',
        category: null,
      })
    })

    it('should parse query from filter string', () => {
      expect(queryFromFilterString('type:apps search')).toEqual({
        type: 'apps',
        copilotApp: null,
        query: 'search',
        category: null,
      })
    })

    it('should parse category from filter string', () => {
      expect(queryFromFilterString('type:apps category:utilities search')).toEqual({
        type: 'apps',
        copilotApp: null,
        query: 'search',
        category: 'utilities',
      })
    })

    it('should handle edge case with no type: prefix', () => {
      expect(queryFromFilterString('search')).toEqual({
        type: null,
        copilotApp: null,
        query: 'search',
        category: null,
      })
    })

    // https://github.com/github/marketplace/issues/4040
    it('handles multi-word category value', () => {
      expect(queryFromFilterString('type:models category:"large context"')).toEqual({
        type: 'models',
        copilotApp: null,
        query: '',
        category: '"large context"',
      })
    })
  })

  describe('removeFilterFromQuery', () => {
    test('empties a query when the filter being removed is the whole query', () => {
      expect(removeFilterFromQuery('publisher', 'publisher:foo')).toEqual('')
    })

    test('removes a filter that has a multi-word value', () => {
      expect(removeFilterFromQuery('category', 'foo category:"large context" bar')).toEqual('foo bar')
    })

    test('no-op when specified filter is not present in the query', () => {
      expect(removeFilterFromQuery('publisher', 'category:foo')).toEqual('category:foo')
    })

    test('removes all instances of the filter', () => {
      expect(removeFilterFromQuery('category', 'category:RAG publisher:meta category:"large context"')).toEqual(
        'publisher:meta',
      )
    })
  })

  describe('getValidFilterValueFromParsedQuery', () => {
    test('returns a valid filter value present in the provided parsed query', () => {
      expect(getValidFilterValueFromParsedQuery('publisher', [['publisher', 'meta']], ['Meta'])).toEqual('Meta')
    })

    test('returns undefined when no valid values are present in the parsed query', () => {
      expect(getValidFilterValueFromParsedQuery('publisher', [['publisher', 'invalid']], ['Meta'])).toBeUndefined()
    })

    test('returns undefined when the specified filter is not present in the parsed query', () => {
      expect(getValidFilterValueFromParsedQuery('publisher', [['category', 'rag']], ['Meta'])).toBeUndefined()
    })
  })
})
