import type {Meta, StoryObj} from '@storybook/react'
import {wrapElement} from './LayoutHelpers'

// Create a wrapper component to render the function
const WrapElementRenderer = ({
  wrappedElement,
  leadingElement,
  key,
}: {
  wrappedElement: React.ReactNode
  leadingElement?: React.ReactNode
  key?: string
}) => {
  return <>{wrapElement(wrappedElement, leadingElement, key)}</>
}

const meta = {
  title: 'Utils/LayoutHelpers',
  component: WrapElementRenderer,
} satisfies Meta<typeof WrapElementRenderer>

export default meta
type Story = StoryObj<typeof meta>

export const Default: Story = {
  args: {
    wrappedElement: <div>Main Content</div>,
  },
}

export const WithLeadingElement: Story = {
  args: {
    wrappedElement: <div>Main Content</div>,
    leadingElement: <div style={{width: 32, height: 32, backgroundColor: '#ccc'}}>Avatar</div>,
  },
}
