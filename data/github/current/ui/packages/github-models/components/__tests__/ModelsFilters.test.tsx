import {screen, within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {SearchAndFilterProviderStack} from '@github-ui/marketplace-common/SearchAndFilterProviderStack'
import ModelsFilters from '../ModelsFilters'
import {mockMarketplaceIndexRoutePayload} from './mocks'

describe('ModelsFilters', () => {
  // https://github.com/github/models/issues/894
  test('shows active filters based on query', () => {
    const parsedQuery = [
      ['category', 'rag'],
      ['publisher', 'meta'],
      ['task', 'embeddings'],
    ]
    const routePayload = mockMarketplaceIndexRoutePayload({parsedQuery})

    render(<ModelsFilters />, {
      routePayload,
      search: '?type=models&query=category:rag%20publisher:meta%20task:embeddings',
    })

    expect(screen.getByRole('button', {name: 'Category: RAG'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Publisher: Meta'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Capability: Embeddings'})).toBeInTheDocument()
  })

  // https://github.com/github/models/issues/1250
  test('changing the publisher goes back to the first page of results', async () => {
    const routePayload = mockMarketplaceIndexRoutePayload()

    const {user} = render(<ModelsFilters />, {routePayload, search: '?type=models&page=3'})

    expect(screen.queryByRole('menu', {name: 'Publisher: All'})).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Publisher: All'}))

    const publisherMenu = screen.getByRole('menu', {name: 'Publisher: All'})
    expect(publisherMenu).toBeInTheDocument()
    const publisherMenuItem = within(publisherMenu).getByRole('menuitemradio', {name: 'Cohere'})
    expect(publisherMenuItem).toBeInTheDocument()

    await user.click(publisherMenuItem)

    expect(window.location.search).toBe('?publisher=Cohere&type=models')
  })

  // https://github.com/github/models/issues/1250
  test('changing the category goes back to the first page of results', async () => {
    const routePayload = mockMarketplaceIndexRoutePayload()

    const {user} = render(<ModelsFilters />, {routePayload, search: '?type=models&page=3'})

    expect(screen.queryByRole('menu', {name: 'Category: All'})).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Category: All'}))

    const categoryMenu = screen.getByRole('menu', {name: 'Category: All'})
    expect(categoryMenu).toBeInTheDocument()
    const categoryMenuItem = within(categoryMenu).getByRole('menuitemradio', {name: 'RAG'})
    expect(categoryMenuItem).toBeInTheDocument()

    await user.click(categoryMenuItem)

    expect(window.location.search).toBe('?category=rag&type=models')
  })

  // https://github.com/github/models/issues/1250
  test('changing the capability goes back to the first page of results', async () => {
    const routePayload = mockMarketplaceIndexRoutePayload()

    const {user} = render(<ModelsFilters />, {routePayload, search: '?type=models&page=3'})

    expect(screen.queryByRole('menu', {name: 'Capability: All'})).not.toBeInTheDocument()

    await user.click(screen.getByRole('button', {name: 'Capability: All'}))

    const capabilityMenu = screen.getByRole('menu', {name: 'Capability: All'})
    expect(capabilityMenu).toBeInTheDocument()
    const capabilityMenuItem = within(capabilityMenu).getByRole('menuitemradio', {name: 'Embeddings'})
    expect(capabilityMenuItem).toBeInTheDocument()

    await user.click(capabilityMenuItem)

    expect(window.location.search).toBe('?task=embeddings&type=models')
  })

  // https://github.com/github/models/issues/1504
  test('publishers are sorted correctly with "All" first and the rest alphabetically by normalized name', async () => {
    const routePayload = mockMarketplaceIndexRoutePayload()
    const {user} = render(<ModelsFilters />, {routePayload})

    await user.click(screen.getByRole('button', {name: /^Publisher:/}))

    const publisherMenu = screen.getByRole('menu', {name: /^Publisher:/})
    const menuItems = within(publisherMenu).getAllByRole('menuitemradio')

    // Check that "All" is always the first item
    expect(menuItems[0]).toHaveTextContent('All')

    // Get the rest of the publisher names (excluding "All")
    const publisherNames = menuItems.slice(1).map(item => item.textContent)

    // Create a sorted copy of the publisher names to compare against
    const sortedPublisherNames = [...publisherNames].sort()

    // Check that the publishers are correctly sorted alphabetically (after "All")
    expect(publisherNames).toEqual(sortedPublisherNames)
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}) {
  return htmlRender(<SearchAndFilterProviderStack>{component}</SearchAndFilterProviderStack>, opts)
}
