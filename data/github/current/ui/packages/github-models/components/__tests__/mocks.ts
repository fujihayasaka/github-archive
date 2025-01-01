import {getIndexRoutePayload, mockSearchResults} from '@github-ui/marketplace-common/mock-data'
import type {IndexPayload, SearchResults} from '@github-ui/marketplace-common'

export function mockMarketplaceIndexRoutePayload(searchResultOverrides?: Partial<SearchResults>): IndexPayload {
  const searchResults = mockSearchResults(searchResultOverrides)
  return getIndexRoutePayload({searchResults})
}
