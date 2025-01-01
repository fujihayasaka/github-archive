import type {Meta, StoryObj} from '@storybook/react'
import type React from 'react'
import {iconMapping, type IconName} from './CustomIcon' // Update this path as needed

// Component to showcase all icons together
const IconList = ({size = 24}: {size?: number | string}) => {
  return (
    <div
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fill, minmax(150px, 1fr))',
        gap: '16px',
      }}
    >
      {(Object.entries(iconMapping) as Array<[IconName, React.ComponentType<{size?: number | string}>]>).map(
        ([name, Icon]) => (
          <div
            key={name}
            style={{
              display: 'flex',
              alignItems: 'center',
              padding: '16px',
            }}
          >
            <Icon size={size} />
            <span style={{marginLeft: '16px'}}>{name}</span>
          </div>
        ),
      )}
    </div>
  )
}

const meta: Meta<typeof IconList> = {
  title: 'Recipes/Pacer/CustomIcon',
  component: IconList,
  tags: ['autodocs'],
  argTypes: {
    size: {
      control: {type: 'range', min: 16, max: 48, step: 4},
      description: 'The size of the icons',
    },
  },
}

export default meta
type Story = StoryObj<typeof IconList>

// Single story showing all icons
export const AllIcons: Story = {
  args: {
    size: 24,
  },
}
