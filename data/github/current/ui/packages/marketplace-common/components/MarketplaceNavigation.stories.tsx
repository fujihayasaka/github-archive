import type {Meta, StoryObj} from '@storybook/react'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {SearchAndFilterProviderStack} from '../contexts/SearchAndFilterProviderStack'
import MarketplaceNavigation, {type Props} from './MarketplaceNavigation'
import {getIndexRoutePayload, mockCategory} from '../test-utils/mock-data'

const meta = {
  title: 'MarketplaceNavigation',
  component: MarketplaceNavigation,
  decorators: [
    Story => (
      <SearchAndFilterProviderStack>
        <div style={{maxWidth: '500px'}}>
          <Story />
        </div>
      </SearchAndFilterProviderStack>
    ),
    storyWrapper({routePayload: getIndexRoutePayload()}),
  ],
} satisfies Meta<typeof MarketplaceNavigation>

export default meta

type Story = StoryObj<typeof MarketplaceNavigation>

export const Example: Story = {
  args: {
    categories: {
      apps: [mockCategory({name: 'API management'}), mockCategory({name: 'Code quality'})],
      actions: [
        mockCategory({name: 'Code review'}),
        mockCategory({name: 'Deployment'}),
        mockCategory({name: 'Testing'}),
      ],
    },
  },
  render: (props: Props) => <MarketplaceNavigation {...props} />,
}
