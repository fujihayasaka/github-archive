import {screen} from '@testing-library/react'
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
})

function render(component: JSX.Element, opts: TestRenderOptions = {}) {
  return htmlRender(<SearchAndFilterProviderStack>{component}</SearchAndFilterProviderStack>, opts)
}
