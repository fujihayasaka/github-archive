import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {renderWithFilterContext} from '../../test-utils/Render'
import MarketplaceHeader from '../MarketplaceHeader'
import {screen} from '@testing-library/react'

jest.mock('@github-ui/react-core/use-feature-flag')
function mockUseFeatureFlag(flag: string, value: boolean): void {
  ;(useFeatureFlag as jest.Mock).mockImplementation(flagName => flagName === flag && value)
}

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
  test('Renders legacy search component when feature flag is disabled', () => {
    renderComponent()

    expect(screen.getByTestId('search-input')).toBeInTheDocument()
  })

  test('Renders new search component when feature flag is enabled', () => {
    mockUseFeatureFlag('marketplace_search_improvements', true)
    renderComponent()

    expect(screen.getByTestId('marketplace-search-filter')).toBeInTheDocument()
  })
})
