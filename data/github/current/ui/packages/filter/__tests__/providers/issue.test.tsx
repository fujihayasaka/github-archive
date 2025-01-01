import {render, screen} from '@testing-library/react'

import {Filter, FILTER_KEYS} from '../../Filter'
import {ParentIssueFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupIssuesMockApi,
} from '../utils/helpers'

describe('Parent Issue', () => {
  setupAsyncErrorHandler()
  setupIssuesMockApi()

  it('should filter and select suggestions', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('parent-issue:featur')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Remove feature flag for beta release')

    await expectFilterValueToBe('parent-issue:github/github#5')
  })

  it('should filter and select suggestions when parent issue contains emoji', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('parent-issue:github/github#4,🐛')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Bug bash for GA 🐛')

    await expectFilterValueToBe('parent-issue:github/github#4,github/github#1')
  })

  it('should filter and select suggestions when parent issue contains custom emoji', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('parent-issue:github/github#4')

    await appendToFilterAndRenderAsyncSuggestions(',:octo')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Load testing')

    await expectFilterValueToBe('parent-issue:github/github#4,github/github#3')
  })

  it('should filter and select suggestions when input ends with colon', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('parent-issue:dashboard:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Create dashboard: for demo')

    await expectFilterValueToBe('parent-issue:github/github#6')
  })

  it('should filter and select suggestions when multiple blocks are present', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue parent-issue:github/github#5,dashboard:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Create dashboard: for demo')

    await expectFilterValueToBe('is:issue parent-issue:github/github#5,github/github#6')
  })

  it('should filter and select key suggestions when negation used', async () => {
    const filterProviders = [new ParentIssueFilterProvider(FILTER_KEYS.parentIssue, {filterTypes: {exclusive: true}})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('-par')

    expect(screen.getByTestId('suggestions-heading')).toHaveTextContent('Exclude')
    await expectSuggestionsToMatchSnapshot()
    await selectSuggestion('Parent issue')

    await expectFilterValueToBe('-parent-issue:')
  })

  it('should filter and select suggestions when added in the start of multiple values', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue parent-issue:,github/github#5,github/github#6 text')

    await appendToFilterAndRenderAsyncSuggestions('Load', 'is:issue parent-issue:'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Load testing :octocat:')

    await expectFilterValueToBe('is:issue parent-issue:github/github#3,github/github#5,github/github#6 text')
  })

  it('should filter and select suggestions when added in the middle of multiple values', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue parent-issue:github/github#5,,github/github#6 text')

    await appendToFilterAndRenderAsyncSuggestions('Load', 'is:issue parent-issue:github/github#5,'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Load testing :octocat:')

    await expectFilterValueToBe('is:issue parent-issue:github/github#5,github/github#3,github/github#6 text')
  })

  it('should filter and select suggestions when added in the end of multiple values', async () => {
    const filterProviders = [new ParentIssueFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue parent-issue:github/github#5,github/github#6, text')

    await appendToFilterAndRenderAsyncSuggestions(
      'Load',
      'is:issue parent-issue:github/github#5,github/github#6,'.length,
    )

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Load testing :octocat:')

    await expectFilterValueToBe('is:issue parent-issue:github/github#5,github/github#6,github/github#3 text')
  })
})
