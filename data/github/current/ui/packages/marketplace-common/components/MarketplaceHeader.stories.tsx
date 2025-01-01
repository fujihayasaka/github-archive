import {Wrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import MarketplaceHeader from './MarketplaceHeader'
import {SearchAndFilterProviderStack} from '../contexts/SearchAndFilterProviderStack'
import {getIndexRoutePayload} from '../test-utils/mock-data'

const meta = {
  title: 'MarketplaceHeader',
  component: MarketplaceHeader,
} satisfies Meta<typeof MarketplaceHeader>

export default meta
type Story = StoryObj<typeof MarketplaceHeader>

const routePayload = getIndexRoutePayload()

export const Example: Story = {
  render: () => {
    return <MarketplaceHeader />
  },
  decorators: [
    Story => (
      <Wrapper routePayload={routePayload} pathname="/marketplace" search="">
        <SearchAndFilterProviderStack>
          <Story />
        </SearchAndFilterProviderStack>
      </Wrapper>
    ),
  ],
}
