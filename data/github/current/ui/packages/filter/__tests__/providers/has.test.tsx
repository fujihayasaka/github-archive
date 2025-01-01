// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {render} from '@github-ui/react-core/test-utils'

import {Filter} from '../../Filter'
import {LabelFilterProvider, MilestoneFilterProvider} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupLabelsMockApi,
} from '../utils/helpers'

const hasValueFilterConfig = {filterTypes: {hasValue: true}}

describe('Has Provider', () => {
  setupLabelsMockApi()
  setupAsyncErrorHandler()

  it('should provide "Has" as a key suggestion for single provider', async () => {
    const filterProviders = [new LabelFilterProvider(hasValueFilterConfig)]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('Ha')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Has')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Label')

    await expectFilterValueToBe('has:label')
  })

  it('should not provide "Has" as a key suggestion when hasValue is undefined or false', async () => {
    const filterProviders = [new LabelFilterProvider(), new MilestoneFilterProvider({filterTypes: {hasValue: false}})]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should provide "Has ..." value suggestion when value is empty', async () => {
    const filterProviders = [new LabelFilterProvider(hasValueFilterConfig)]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Has label')

    await expectFilterValueToBe('has:label')
  })

  it('should not provide "Has ..." value suggestion when multiple values exists', async () => {
    const filterProviders = [new LabelFilterProvider(hasValueFilterConfig)]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('label:a11y,')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should not provide suggestion for filter provider previously used', async () => {
    const filterProviders = [
      new LabelFilterProvider(hasValueFilterConfig),
      new MilestoneFilterProvider(hasValueFilterConfig),
    ]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('has:label has:')

    await expectSuggestionsToMatchSnapshot()
  })

  it('should not provide suggestion for filter provider previously used in the same block', async () => {
    const filterProviders = [
      new LabelFilterProvider(hasValueFilterConfig),
      new MilestoneFilterProvider(hasValueFilterConfig),
    ]

    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('has:label,')

    await expectSuggestionsToMatchSnapshot()
  })
})
