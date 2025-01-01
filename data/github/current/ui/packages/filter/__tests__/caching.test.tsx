import {render} from '@github-ui/react-core/test-utils'
import {hasMatch} from 'fzy.js'

import {Filter} from '../Filter'
import {labels, labelSuggestions} from '../mocks'
import {LabelFilterProvider} from '../providers'
import {setupExpectedAsyncErrorHandler, updateFilterValue} from '../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectFilterValueToBe,
  expectSuggestionsToBeEmpty,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
} from './utils/helpers'

const globalFetch = global.fetch

jest.setTimeout(20_000)

describe('Caching suggestions', () => {
  const set = new Set()
  let error: Error | null = null

  beforeEach(() => {
    global.fetch = jest.fn(url => {
      const parsedUrl = new URL(url, window.location.origin)
      const filterValue = parsedUrl.searchParams.get('q')
      // fail the test if fetch is called more than once for the same value
      if (set.has(url)) {
        error = new Error('Error: fetch should not be called more than once for value')
        return Promise.reject(error)
      }
      set.add(url)
      return Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            labels: filterValue
              ? labels.filter(l => {
                  return hasMatch(filterValue, l.name)
                })
              : labelSuggestions,
          }),
      })
    }) as jest.Mock
    setupExpectedAsyncErrorHandler()
  })

  afterEach(() => {
    set.clear()
    jest.restoreAllMocks()
    global.fetch = globalFetch
  })

  function expectFetchToBeCalledOnce() {
    if (error) throw error
  }

  it('should filter and select cached suggestions on empty value', async () => {
    const filterProviders = [new LabelFilterProvider()]
    const {user} = render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:')
    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await appendToFilterAndRenderAsyncSuggestions('a')
    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await user.keyboard('{Backspace}')

    await expectFilterValueToBe('label:')
    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('No label')
    await expectFilterValueToBe('no:label')
  })

  it('should filter and select cached suggestions on value', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a')
    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('triage')

    await expectFilterValueToBe('label:triage')

    await appendToFilterAndRenderAsyncSuggestions(',b')
    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('accessibility review')

    await expectFilterValueToBe('label:triage,"accessibility review"')
  })

  it('should filter and select cached suggestions on backspace', async () => {
    const filterProviders = [new LabelFilterProvider()]
    const {user} = render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:')
    expectFetchToBeCalledOnce()

    await appendToFilterAndRenderAsyncSuggestions('a11')
    expectFetchToBeCalledOnce()

    await appendToFilterAndRenderAsyncSuggestions('y')
    expectFetchToBeCalledOnce()

    await expectSuggestionsToBeEmpty()

    await user.keyboard('{Backspace>4}')
    expectFetchToBeCalledOnce()

    await expectFilterValueToBe('label:')
  })

  it('should not display selected from cached suggestion', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:c')

    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('accessibility review')

    await expectFilterValueToBe('label:"accessibility review"')

    await appendToFilterAndRenderAsyncSuggestions(',c')

    expectFetchToBeCalledOnce()

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('batch')

    await expectFilterValueToBe('label:"accessibility review",batch')
  })
})
