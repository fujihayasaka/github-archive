import type {Meta, StoryObj} from '@storybook/react'
import {RocketIcon} from '@primer/octicons-react'

import {Card} from './Card'

const meta: Meta<typeof Card> = {
  title: 'Recipes/Pacer/Card',
  component: Card,
  parameters: {
    layout: 'centered',
  },
  tags: ['autodocs'],
}

export default meta
type Story = StoryObj<typeof Card>

// Use a button card instead of a link card to avoid router context issues
function CardExample() {
  return (
    <div style={{maxWidth: '400px'}}>
      <Card onClick={() => alert('Card clicked!')}>
        <Card.Icon icon={RocketIcon} color="auburn" />
        <Card.Heading>Button Card Example</Card.Heading>
        <Card.Description>Click this card to trigger an action instead of navigation.</Card.Description>
        <Card.Metadata>
          <div style={{display: 'flex', flexDirection: 'column', gap: '4px'}}>
            <div>
              <strong>Date/Time:</strong> 2025-04-10 12:20:29
            </div>
            <div>
              <strong>User:</strong> dipree
            </div>
          </div>
        </Card.Metadata>
      </Card>
    </div>
  )
}

export const Default: Story = {
  render: () => <CardExample />,
}
