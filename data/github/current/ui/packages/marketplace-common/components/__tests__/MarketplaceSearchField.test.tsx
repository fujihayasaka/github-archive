import {act, screen} from '@testing-library/react'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {mockSearchResults} from '../../test-utils/mock-data'
import {renderWithFilterContext} from '../../test-utils/Render'
import MarketplaceSearchField from '../MarketplaceSearchField'

function setupResizeObserverMock() {
  class MockResizeObserver implements ResizeObserver {
    observe() {}
    unobserve() {}
    disconnect() {}
  }

  Object.defineProperty(window, 'ResizeObserver', {
    writable: true,
    configurable: true,
    value: MockResizeObserver,
  })
}

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

beforeEach(() => {
  jest.resetAllMocks()

  setupResizeObserverMock()

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return mockSearchResults()
    },
  })
})

const renderComponent = (search?: string) => renderWithFilterContext(<MarketplaceSearchField />, {}, {search})

describe('MarketplaceSearchField', () => {
  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation((message: string) => {
      // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
      // * any errors that are not related to the async nature of the component.
      if (!message.includes?.('wrapped in act(')) {
        // eslint-disable-next-line no-console
        console.error(message)
      }
    })

    global.matchMedia = media => ({
      addListener: jest.fn(),
      removeListener: jest.fn(),
      matches: media === '(min-width: 1000px)',
      addEventListener: jest.fn(),
      removeEventListener: jest.fn(),
      dispatchEvent: jest.fn(),
      onchange: jest.fn(),
      media,
    })
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  test('Renders filter component', () => {
    renderComponent()

    expect(screen.getByTestId('marketplace-search-filter')).toBeInTheDocument()
  })

  describe('when searching', () => {
    it('should work', async () => {
      const {user} = renderComponent()

      const searchInput = screen.getByRole('combobox')
      await user.type(searchInput, 'test{Enter}')

      expect(searchInput).toHaveValue('test')
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace?query=test')
    })

    test('in keyword adds type query parameter', async () => {
      const {user} = renderComponent()

      const searchInput = screen.getByRole('combobox')
      expect(searchInput).toHaveValue('')

      await user.type(searchInput, 'type:apps test{Enter}')
      expect(searchInput).toHaveValue('type:apps test')

      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace?query=test&type=apps')
    })

    test('in and category keywords with type and category query parameters', async () => {
      const {user} = renderComponent()

      const searchInput = screen.getByRole('combobox')
      expect(searchInput).toHaveValue('')

      await user.type(searchInput, 'type:apps category:automation test{Enter}')
      expect(searchInput).toHaveValue('type:apps category:automation test')

      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace?query=test&category=automation&type=apps')
    })

    test('type:copilot keyword adds copilot_app and type query parameters', async () => {
      const {user} = renderComponent()

      const searchInput = screen.getByRole('combobox')
      expect(searchInput).toHaveValue('')

      await user.type(searchInput, 'type:copilot test{Enter}')
      expect(searchInput).toHaveValue('type:copilot test')

      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace?query=test&type=apps&copilot_app=true')
    })

    // https://github.com/github/models/issues/873
    test('clearing search field when searching in models correctly updates sort', async () => {
      renderComponent('?type=models&query=some+search')
      const clearButton = screen.getByTestId('filter-clear-query')

      await act(() => {
        clearButton.click()
      })

      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace')
    })

    test('selecting a filter updates the query', async () => {
      const {user} = renderComponent()

      const searchInput = await screen.findByRole('combobox')

      // await user.click(searchInput)
      await act(() => searchInput.focus())
      expect(searchInput).toHaveFocus()

      await user.keyboard('{ArrowDown}')

      const listingTypeOption = screen.getByRole('option', {name: /Listing Type/})
      expect(listingTypeOption).toBeInTheDocument()
      expect(listingTypeOption).toHaveAttribute('aria-selected', 'true')
      await act(() => listingTypeOption.click())

      // clicking the keyword option should not execute query
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(0)

      await user.keyboard('{ArrowDown}')

      const appsOption = screen.getByRole('option', {name: /Copilot extensions/})
      expect(appsOption).toBeInTheDocument()
      expect(appsOption).toHaveAttribute('aria-selected', 'true')
      await act(() => appsOption.click())

      // after selecting an option the query should be updated
      expect(mockVerifiedFetchJSON).toHaveBeenCalledWith('/marketplace?type=apps&copilot_app=true')
    })
  })

  describe('when loading the page', () => {
    test('prefills search field with type, query, and category', async () => {
      renderComponent('?type=apps&category=automation&query=some+search')

      const searchInput = await screen.findByRole('combobox')
      expect(searchInput).toHaveValue('type:apps category:automation some search')
    })

    test('prefills search field with copilot', async () => {
      renderComponent('?type=apps&copilot_app=true&query=some+search')

      const searchInput = await screen.findByRole('combobox')
      expect(searchInput).toHaveValue('type:copilot some search')
    })

    test('adds initial trailing space if search field is not empty and no query', async () => {
      renderComponent('?type=apps')

      const searchInput = await screen.findByRole('combobox')
      expect(searchInput).toHaveValue('type:apps ')
    })
  })
})
