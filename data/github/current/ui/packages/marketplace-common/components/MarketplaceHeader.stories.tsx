import type {Meta, StoryObj} from '@storybook/react'
import MarketplaceHeader from './MarketplaceHeader'

const meta = {
  title: 'MarketplaceHeader',
  component: MarketplaceHeader,
} satisfies Meta<typeof MarketplaceHeader>

export default meta
type Story = StoryObj<typeof MarketplaceHeader>

export const Example: Story = {
  render: () => {
    return <MarketplaceHeader />
  },
}
