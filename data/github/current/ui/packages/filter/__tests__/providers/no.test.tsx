// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {render} from '@github-ui/react-core/test-utils'

import {Filter} from '../../Filter'
import {LabelFilterProvider, StateFilterProvider, StatusFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupLabelsMockApi,
} from '../utils/helpers'

describe('No Provider', () => {
  setupLabelsMockApi()
  setupAsyncErrorHandler()

  it('should provide "No" as a key suggestion for single valueless provider', async () => {
    const filterProviders = [new LabelFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('N')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('No')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Label')

    await expectFilterValueToBe('no:label')
  })

  it('should provide "No" as a key suggestion for multiple valueless providers', async () => {
    const filterProviders = [new LabelFilterProvider(), new StateFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('N')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('No')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Label')

    await expectFilterValueToBe('no:label')
  })

  it('should not provide "No" as a key suggestion when no valueless providers exists', async () => {
    const filterProviders = [
      new LabelFilterProvider({filterTypes: {valueless: false}}),
      new StateFilterProvider('mixed', {filterTypes: {valueless: false}}),
    ]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should provide "No ..." value suggestion when value is empty', async () => {
    const filterProviders = [new LabelFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('No label')

    await expectFilterValueToBe('no:label')
  })

  it('should not provide "No ..." value suggestion when value exists', async () => {
    const filterProviders = [new LabelFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should not provide "No ..." value suggestion when multiple values exists', async () => {
    const filterProviders = [new LabelFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11y,')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should not provide suggestion for filter provider previously used', async () => {
    const filterProviders = [new LabelFilterProvider(), new StatusFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('no:label no:')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should not provide suggestion for filter provider previously used in the same block', async () => {
    const filterProviders = [new LabelFilterProvider(), new StatusFilterProvider()]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('no:label,')

    await expectSuggestionsToMatchSnapshot()
  })
})
