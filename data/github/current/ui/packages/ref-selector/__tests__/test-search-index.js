import {SearchIndex} from '../search-index'
import {afterEach, beforeEach, describe, expect, it} from '@github-ui/tests'

describe('SearchIndex', function () {
  let index
  let renders = 0
  // mock parent component
  const selector = {render: () => renders++}

  beforeEach(function () {
    index = new SearchIndex('branch', selector, '/', 'cache-1', 'nwo')
  })

  afterEach(function () {
    renders = 0
  })

  it('searching', function () {
    index.knownItems = ['abc', 'foo-1', 'foo', '123-foo', 'abcfoo123']
    index.search('foo')
    expect.deepEqual(index.currentSearchResult, ['foo', 'foo-1', '123-foo', 'abcfoo123'])
    expect.isTrue(index.exactMatchFound)

    // extra test that prefix matches are always first regardless of their position in the corpus
    index.knownItems = ['blah', 'whatever-test', 'my-test-string', 'test-123']
    index.search('test')
    expect.equal(index.currentSearchResult.length, 3)
    expect.equal(index.currentSearchResult[0], 'test-123')
    expect.isFalse(index.exactMatchFound)

    // test emoji searching
    index.knownItems = ['abc', 'foo-1', 'foo', '123-foo', 'abcfoo123', 'makes-me-want-to-😃', '😃 :)', '😃']
    index.search('😃')
    expect.equal(index.currentSearchResult.length, 3)
    expect.equal(index.currentSearchResult[0], '😃')
    expect.equal(index.currentSearchResult[1], '😃 :)')
    expect.equal(index.currentSearchResult[2], 'makes-me-want-to-😃')
    expect.isTrue(index.exactMatchFound)
  })

  it('localstorage roundtripping', function () {
    const response = {
      refs: ['foo-1', 'abc-foo'],
      cacheKey: 'cache-123',
    }
    index.flushToLocalStorage(JSON.stringify(response))

    // expect that a new index object loads from localstorage
    let dupIndex = new SearchIndex('branch', selector, '/', 'cache-123', 'nwo')
    dupIndex.bootstrapFromLocalStorage()
    expect.deepEqual(dupIndex.knownItems, response.refs)

    // expect that a new index with a later cache-key doesn't use the stale data
    dupIndex = new SearchIndex('branch', selector, '/', 'cache-456', 'nwo')
    dupIndex.bootstrapFromLocalStorage()
    expect.notDeepEqual(dupIndex.knownItems, response.refs)

    // expect that a new index with a different nwo doesn't use the data
    dupIndex = new SearchIndex('branch', selector, '/', 'cache-123', 'other-nwo')
    dupIndex.bootstrapFromLocalStorage()
    expect.notDeepEqual(dupIndex.knownItems, response.refs)
  })
})
