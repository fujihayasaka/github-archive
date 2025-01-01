import {renderWithFilterContext} from '../../test-utils/Render'
import MarketplaceHeader from '../MarketplaceHeader'
import {screen} from '@testing-library/react'

function renderComponent() {
  return renderWithFilterContext(<MarketplaceHeader />)
}

describe('MarketplaceHeader', () => {
  beforeEach(() => {
    jest.spyOn(console, 'error').mockImplementation((message: string) => {
      // * Because Filter is asynchronous, there are console errors that are thrown, but expected. This will rethrow
      // * any errors that are not related to the async nature of the component.
      if (!message.includes?.('wrapped in act(')) {
        // eslint-disable-next-line no-console
        console.error(message)
      }
    })
  })

  afterEach(() => {
    jest.restoreAllMocks()
  })

  test('Renders search component', () => {
    renderComponent()

    expect(screen.getByTestId('marketplace-search-filter')).toBeInTheDocument()
  })
})
