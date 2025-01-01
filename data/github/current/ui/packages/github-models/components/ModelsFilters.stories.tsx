import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import ModelsFilters from './ModelsFilters'
import {SearchAndFilterProviderStack} from '@github-ui/marketplace-common/SearchAndFilterProviderStack'
import {parametersConfig} from '../utils/story-utils'
import {getIndexRoutePayload} from '@github-ui/marketplace-common/mock-data'

const meta: Meta = {
  title: 'Apps/GitHub Models/ModelsFilters',
  component: ModelsFilters,
  parameters: parametersConfig,
}

export default meta

export const Example: StoryObj = {
  render: () => <ModelsFilters />,
  decorators: [
    Story => (
      <Wrapper routePayload={getIndexRoutePayload()} search="?type=models">
        <SearchAndFilterProviderStack>
          <Story />
        </SearchAndFilterProviderStack>
      </Wrapper>
    ),
  ],
}
