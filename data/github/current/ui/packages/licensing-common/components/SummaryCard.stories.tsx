import type {Meta, StoryObj} from '@storybook/react'
import {SummaryCard} from './SummaryCard'
import {ProductActivationState} from '../types/product-activation-state'
import {ShieldCheckIcon} from '@primer/octicons-react'

const meta = {
  title: 'Apps/LicensingCommon/SummaryCard',
  component: SummaryCard,
  args: {
    productActivationState: ProductActivationState.Active,
    headerIconComponent: ShieldCheckIcon,
    title: 'Advanced Security',
    headerMenu: <div>Default Header Menu</div>,
    children: <div>Default Card Body</div>,
  },
} satisfies Meta<typeof SummaryCard>

export default meta

type Story = StoryObj<typeof SummaryCard>

export const Default: Story = {}
