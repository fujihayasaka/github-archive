import {render, screen, waitFor} from '@testing-library/react'

import {Filter} from '../../Filter'
import {
  AssigneeFilterProvider,
  AuthorFilterProvider,
  CommenterFilterProvider,
  InvolvesFilterProvider,
  MentionsFilterProvider,
  ReviewedByFilterProvider,
  ReviewRequestedFilterProvider,
  UserFilterProvider,
  UserReviewRequestedFilterProvider,
} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  appendToFilterAndRenderAsyncSuggestions,
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
  setupUsersMockApi,
} from '../utils/helpers'

describe('Assignee', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('ensures `signed-in user` is part of accessible name for `@me` value', async () => {
    const filterProviders = [new AssigneeFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('assignee:')

    expect(screen.getByRole('option', {name: '@me, Signed-in user'})).toBeInTheDocument()
  })

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new AssigneeFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('assignee:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('assignee:dusave')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new AssigneeFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('duuuuuus')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })

  it('should filter and select suggestions when added in the start of multiple values', async () => {
    const filterProviders = [new AssigneeFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:issue assignee:,2percentsilk text')

    await appendToFilterAndRenderAsyncSuggestions('dus', 'is:issue assignee:'.length)

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('is:issue assignee:dusave,2percentsilk text')
  })

  it('should not show a wildcard suggestion by default', async () => {
    const filterProviders = [new AssigneeFilterProvider({})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('assignee:')

    expect(screen.queryByRole('option', {name: 'Has Assignee, Assignee'})).not.toBeInTheDocument()
  })

  it('should show a wildcard suggestion for has if showHasValue is true', async () => {
    const filterProviders = [new AssigneeFilterProvider({showHasValue: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('assignee:')

    expect(screen.getByRole('option', {name: 'Has Assignee, Assignee'})).toBeInTheDocument()

    await selectSuggestion('Has assignee')

    await expectFilterValueToBe('assignee:*')
  })
})

describe('Author', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new AuthorFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('author:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('author:dusave')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new AuthorFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('duuuuuus')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Commenter', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new CommenterFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('commenter:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('commenter:dusave')
  })
})

describe('Involves', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new InvolvesFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('involves:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('involves:dusave')
  })
})

describe('Mentions', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new MentionsFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('mentions:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('mentions:dusave')
  })
})

describe('ReviewedBy', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new ReviewedByFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('reviewed-by:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('reviewed-by:dusave')
  })
})

describe('ReviewedRequested', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new ReviewRequestedFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('review-requested:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('review-requested:dusave')
  })
})

describe('User', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new UserFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('user:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('user:dusave')
  })
})

describe('UserReviewRequested', () => {
  setupAsyncErrorHandler()
  setupUsersMockApi()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new UserReviewRequestedFilterProvider({showAtMe: true})]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('user-review-requested:dusa')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('dusave')

    await expectFilterValueToBe('user-review-requested:dusave')
  })
})
