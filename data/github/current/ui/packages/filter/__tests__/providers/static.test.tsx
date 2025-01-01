// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {render, screen, waitFor} from '@testing-library/react'

import {Filter} from '../../Filter'
import {
  ArchivedFilterProvider,
  CommentsFilterProvider,
  DraftFilterProvider,
  InFilterProvider,
  InteractionsFilterProvider,
  IsFilterProvider,
  LinkedFilterProvider,
  ReactionsFilterProvider,
  ReasonFilterProvider,
  ReviewFilterProvider,
} from '../../providers'
import {updateFilterValue} from '../../test-utils'
import {
  expectFilterValueToBe,
  expectSuggestionsToMatchSnapshot,
  selectSuggestion,
  setupAsyncErrorHandler,
} from '../utils/helpers'

describe('Archived', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new ArchivedFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('archived:tr')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('true')

    await expectFilterValueToBe('archived:true')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new ArchivedFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Comments', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new CommentsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('comments:Less')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Less than 10')

    await expectFilterValueToBe('comments:<10')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new CommentsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Draft', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new DraftFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('draft:tr')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('true')

    await expectFilterValueToBe('draft:true')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new DraftFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Interactions', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new InteractionsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('interactions:Less')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Less than 10')

    await expectFilterValueToBe('interactions:<10')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new InteractionsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Is', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new IsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:iss')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Issue')

    await expectFilterValueToBe('is:issue')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new IsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('Isssss')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })

  it("should show 'public' suggestion", async () => {
    const filterProviders = [new IsFilterProvider(['issue', 'pr', 'private', 'public'])]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:pub')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Public')

    await expectFilterValueToBe('is:public')
  })

  it("should not show 'public' suggestion", async () => {
    const filterProviders = [new IsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('is:pub')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('In', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new InFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('in:comm')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Comments')

    await expectFilterValueToBe('in:comments')
  })

  it('should filter multiple values and select suggestions based on name', async () => {
    const filterProviders = [new InFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('in:comments,')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Title')

    await expectFilterValueToBe('in:comments,title')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new InFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('Inn')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Linked', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new LinkedFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('linked:p')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Pull Request')

    await expectFilterValueToBe('linked:pr')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new LinkedFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('Prrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Reactions', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new ReactionsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('reactions:Less')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Less than 10')

    await expectFilterValueToBe('reactions:<10')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new ReactionsFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Reason', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new ReasonFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('reason:comp')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('Completed')

    await expectFilterValueToBe('reason:completed')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new ReasonFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})

describe('Review', () => {
  setupAsyncErrorHandler()

  it('should filter and select suggestions based on name', async () => {
    const filterProviders = [new ReviewFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('review:no')

    await expectSuggestionsToMatchSnapshot()

    await selectSuggestion('No reviews')

    await expectFilterValueToBe('review:none')
  })

  it('should not show any suggestions based on invalid name', async () => {
    const filterProviders = [new ReviewFilterProvider()]
    render(<Filter id="test-filter-bar" label="Filter" providers={filterProviders} />)

    await updateFilterValue('tttrrr')

    await waitFor(() => {
      expect(screen.getByTestId('filter-results')).toBeEmptyDOMElement()
    })
  })
})
