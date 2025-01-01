import {screen, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {ModelsSortMenu} from '../ModelsSortMenu'
import {SearchAndFilterProviderStack} from '@github-ui/marketplace-common/SearchAndFilterProviderStack'
import {mockResizeObserver} from '../../routes/playground/components/GettingStartedDialog/__tests__/mocks'
import {mockMarketplaceIndexRoutePayload} from './mocks'

describe('ModelsSortMenu', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all ModelsSortMenu
    // tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders with default sort order when no search query is specified in the URL', async () => {
    const routePayload = mockMarketplaceIndexRoutePayload()

    const {container, user} = render(<ModelsSortMenu />, {routePayload, search: '?type=models'})

    const menuToggleButton = within(container).getByRole('button', {name: 'Sort: Recently added'})
    expect(menuToggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Sort: Recently added'})).not.toBeInTheDocument()

    await user.click(menuToggleButton)

    const sortMenu = screen.getByRole('menu', {name: 'Sort: Recently added'})
    expect(sortMenu).toBeInTheDocument()
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Alphabetical'})).toHaveAttribute('aria-checked', 'false')
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Recently added'})).toHaveAttribute(
      'aria-checked',
      'true',
    )
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Input token limit'})).toHaveAttribute(
      'aria-checked',
      'false',
    )
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Output token limit'})).toHaveAttribute(
      'aria-checked',
      'false',
    )
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Popularity'})).toHaveAttribute('aria-checked', 'false')
  })

  test('renders when search query in the URL specifies a sort order', async () => {
    const routePayload = mockMarketplaceIndexRoutePayload({parsedQuery: [['sort', 'name-asc']]})

    const {container, user} = render(<ModelsSortMenu />, {routePayload, search: '?type=models&query=sort:name-asc'})

    const menuToggleButton = within(container).getByRole('button', {name: 'Sort: Alphabetical'})
    expect(menuToggleButton).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Sort: Alphabetical'})).not.toBeInTheDocument()

    await user.click(menuToggleButton)

    const sortMenu = screen.getByRole('menu', {name: 'Sort: Alphabetical'})
    expect(sortMenu).toBeInTheDocument()
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Alphabetical'})).toHaveAttribute('aria-checked', 'true')
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Recently added'})).toHaveAttribute(
      'aria-checked',
      'false',
    )
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Input token limit'})).toHaveAttribute(
      'aria-checked',
      'false',
    )
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Output token limit'})).toHaveAttribute(
      'aria-checked',
      'false',
    )
    expect(within(sortMenu).getByRole('menuitemradio', {name: 'Popularity'})).toHaveAttribute('aria-checked', 'false')
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}) {
  return htmlRender(<SearchAndFilterProviderStack>{component}</SearchAndFilterProviderStack>, opts)
}
