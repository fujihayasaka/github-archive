import {screen} from '@testing-library/react'
import ResultList from '../ResultList'
import {getIndexRoutePayload} from '@github-ui/marketplace-common/mock-data'
import type {IndexPayload} from '@github-ui/marketplace-common'
import {renderWithFilterContext} from '@github-ui/marketplace-common/test-utils'

jest.mock('@github-ui/use-navigate')

beforeEach(() => {
  const {useSearchParams} = jest.requireMock('@github-ui/use-navigate')
  useSearchParams.mockImplementation(() => [new URLSearchParams(), jest.fn()])
})

const renderComponent = (searchResults: IndexPayload['searchResults']) => {
  renderWithFilterContext(<ResultList categories={getIndexRoutePayload().categories} />, {searchResults})
}

describe('ResultList', () => {
  describe('When there are search results', () => {
    test('Renders the filters', () => {
      renderComponent(getIndexRoutePayload().searchResults)

      expect(screen.getByTestId('filter-button')).toBeInTheDocument()
      expect(screen.getByTestId('creator-button')).toBeInTheDocument()
      expect(screen.getByTestId('sort-button')).toBeInTheDocument()
    })

    test('Renders the search results', () => {
      const results = getIndexRoutePayload().searchResults
      renderComponent(results)

      expect(screen.getByTestId('search-results')).toBeInTheDocument()
      for (const result of results.results) {
        expect(screen.getByText(result.name)).toBeInTheDocument()
      }
    })
  })

  describe('When there are no search results', () => {
    test('Render the filters', () => {
      renderComponent({results: [], total: 0, totalPages: 0})

      expect(screen.getByTestId('filter-button')).toBeInTheDocument()
      expect(screen.getByTestId('creator-button')).toBeInTheDocument()
      expect(screen.getByTestId('sort-button')).toBeInTheDocument()
    })

    test('Renders the blankslate', () => {
      renderComponent({results: [], total: 0, totalPages: 0})

      expect(screen.getByText('No results')).toBeInTheDocument()
      expect(screen.getByText('Try searching by different keywords.')).toBeInTheDocument()
    })
  })
})
