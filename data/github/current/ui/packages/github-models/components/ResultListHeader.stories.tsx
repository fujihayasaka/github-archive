import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {ResultListHeader} from './ResultListHeader'
import {parametersConfig} from '../utils/story-utils'
import {SearchAndFilterProviderStack} from '@github-ui/marketplace-common/SearchAndFilterProviderStack'
import {getIndexRoutePayload, mockModelListing} from '@github-ui/marketplace-common/mock-data'

const meta: Meta = {
  title: 'Apps/GitHub Models/ResultListHeader',
  component: ResultListHeader,
  parameters: parametersConfig,
}

export default meta

const recentModels = [
  mockModelListing({
    id: '1',
    friendly_name: 'Recent Model A',
    logo_url: '/images/modules/marketplace/models/families/openai.svg',
  }),
  mockModelListing({
    id: '2',
    friendly_name: 'Recent Model B',
    logo_url: '/images/modules/marketplace/models/families/meta.svg',
  }),
  mockModelListing({
    id: '3',
    friendly_name: 'Recent Model C',
    logo_url: '/images/modules/marketplace/models/families/mistral ai.svg',
  }),
]

const popularModels = [
  mockModelListing({
    id: '4',
    friendly_name: 'Popular Model A',
    logo_url: '/images/modules/marketplace/models/families/core42.svg',
  }),
  mockModelListing({
    id: '5',
    friendly_name: 'Popular Model B',
    logo_url: '/images/modules/marketplace/models/families/ai21 labs.svg',
  }),
  mockModelListing({
    id: '6',
    friendly_name: 'Popular Model C',
    logo_url: '/images/modules/marketplace/models/families/cohere.svg',
  }),
]

export const Example: StoryObj = {
  decorators: [
    Story => (
      <Wrapper routePayload={getIndexRoutePayload({recentModels, popularModels})} search="?type=models">
        <SearchAndFilterProviderStack>
          <Story />
        </SearchAndFilterProviderStack>
      </Wrapper>
    ),
  ],
}
