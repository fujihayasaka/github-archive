import type {Meta, StoryObj} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {ModelsSortMenu} from './ModelsSortMenu'
import {parametersConfig} from '../utils/story-utils'
import type {AppPayloadWithFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {SearchAndFilterProviderStack} from '@github-ui/marketplace-common/SearchAndFilterProviderStack'
import type {IndexPayload, SearchResults} from '@github-ui/marketplace-common'
import {getIndexRoutePayload, mockSearchResults} from '@github-ui/marketplace-common/mock-data'

const meta = {
  title: 'Apps/GitHub Models/ModelsSortMenu',
  component: ModelsSortMenu,
  parameters: parametersConfig,
} satisfies Meta

export default meta

const appPayload: AppPayloadWithFeatureFlags = {enabled_features: {github_models_popularity_sort: true}}
const pathname = '/marketplace'

function getRoutePayload(parsedQuery: SearchResults['parsedQuery']): IndexPayload {
  const searchResults = mockSearchResults({parsedQuery})
  return getIndexRoutePayload({searchResults})
}

export const DefaultSortOrder: StoryObj = {
  render: () => <ModelsSortMenu />,
  decorators: [
    Story => (
      <Wrapper routePayload={getRoutePayload([])} appPayload={appPayload} pathname={pathname} search="?type=models">
        <SearchAndFilterProviderStack>
          <Story />
        </SearchAndFilterProviderStack>
      </Wrapper>
    ),
  ],
}

export const AlphabeticalSortOrder: StoryObj = {
  render: () => <ModelsSortMenu />,
  decorators: [
    Story => (
      <Wrapper
        routePayload={getRoutePayload([['sort', 'name-asc']])}
        appPayload={appPayload}
        pathname={pathname}
        search="?type=models&query=sort:name-asc"
      >
        <SearchAndFilterProviderStack>
          <Story />
        </SearchAndFilterProviderStack>
      </Wrapper>
    ),
  ],
}
