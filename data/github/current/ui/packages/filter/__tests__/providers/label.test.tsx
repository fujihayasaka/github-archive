import {render, screen} from '@testing-library/react'

import {Filter} from '../../Filter'
import {LabelFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupLabelsMockApi,
} from '../utils/helpers'

describe('Label', () => {
  setupAsyncErrorHandler()
  setupLabelsMockApi()

  it('should filter and select suggestions', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('a11y')

    await expectFilterValueToBe('label:a11y')
  })

  it('should filter and select suggestions when label contains emoji', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11y,🐛')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('🐛 bug')

    await expectFilterValueToBe('label:a11y,"🐛 bug"')
  })

  it('should filter and select suggestions when label contains custom emoji', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11y,"🐛 bug"')

    await appendToFilterAndRenderAsyncSuggestions(',:octo')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('GitHub')

    await expectFilterValueToBe('label:a11y,"🐛 bug",":octocat: GitHub 😄"')
  })

  it('should filter and select suggestions when input ends with colon', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:team:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('team:engineering')

    await expectFilterValueToBe('label:team:engineering')
  })

  it('should filter and select suggestions when input contains multiple colons', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11y,"🐛 bug",":octocat: GitHub 😄",team:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('team:engineering')

    await expectFilterValueToBe('label:a11y,"🐛 bug",":octocat: GitHub 😄",team:engineering')
  })

  it('should filter and select suggestions when multiple blocks', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue label:a11y,"🐛 bug",":octocat: GitHub 😄",team:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('team:engineering')

    await expectFilterValueToBe('is:issue label:a11y,"🐛 bug",":octocat: GitHub 😄",team:engineering')
  })

  it('should filter and select key suggestions when negation used', async () => {
    const filterProviders = [new LabelFilterProvider({filterTypes: {exclusive: true}})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('-lab')

    expect(screen.getByTestId('suggestions-heading')).toHaveTextContent('Exclude')
    await expectSuggestionsToMatchSnapshot()
    await selectSuggestion('Label')

    await expectFilterValueToBe('-label:')
  })

  it('should filter and select suggestions when added in the start of multiple values', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue label:,a11y,"🐛 bug",":octocat: GitHub 😄" text')

    await appendToFilterAndRenderAsyncSuggestions('team:', 'is:issue label:'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('team:engineering')

    await expectFilterValueToBe('is:issue label:team:engineering,a11y,"🐛 bug",":octocat: GitHub 😄" text')
  })

  it('should filter and select suggestions when added in the middle of multiple values', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue label:a11y,"🐛 bug",,":octocat: GitHub 😄" text')

    await appendToFilterAndRenderAsyncSuggestions('team:', 'is:issue label:a11y,"🐛 bug",'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('team:engineering')

    await expectFilterValueToBe('is:issue label:a11y,"🐛 bug",team:engineering,":octocat: GitHub 😄" text')
  })

  it('should filter and select suggestions when added in the end of multiple values', async () => {
    const filterProviders = [new LabelFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11y,"🐛 bug",":octocat: GitHub 😄" text')

    await appendToFilterAndRenderAsyncSuggestions(',team', 'label:a11y,"🐛 bug",":octocat: GitHub 😄"'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('team:engineering')

    await expectFilterValueToBe('label:a11y,"🐛 bug",":octocat: GitHub 😄",team:engineering text')
  })
})
