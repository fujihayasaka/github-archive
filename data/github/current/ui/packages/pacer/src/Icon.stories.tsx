import type {Meta, StoryObj} from '@storybook/react'
import {Icon} from './Icon'
import {RocketIcon, StarIcon, BellIcon, HeartIcon} from '@primer/octicons-react'

// Define available colors
const allColors = [
  'auburn',
  'blue',
  'brown',
  'coral',
  'cyan',
  'gray',
  'green',
  'indigo',
  'lemon',
  'lime',
  'olive',
  'orange',
  'pine',
  'pink',
  'plum',
  'purple',
  'red',
  'teal',
  'yellow',
] as const

const meta: Meta<typeof Icon> = {
  title: 'Recipes/Pacer/Icon',
  component: Icon,
  tags: ['autodocs'],
  argTypes: {
    icon: {
      control: {
        type: 'select',
        options: ['RocketIcon', 'StarIcon', 'BellIcon', 'HeartIcon'],
        mapping: {
          RocketIcon,
          StarIcon,
          BellIcon,
          HeartIcon,
        },
      },
      description: 'The icon component to render',
    },
    hasBackground: {
      control: 'boolean',
      description: 'Whether the icon should have a background',
    },
    color: {
      control: 'select',
      options: allColors,
      description: 'The color of the icon',
    },
    size: {
      control: {type: 'range', min: 8, max: 64, step: 2},
      description: 'The size of the icon in pixels',
    },
  },
  parameters: {
    docs: {
      description: {
        component:
          'Icon component that renders an SVG icon with various styling options including color, size, and background.',
      },
    },
  },
}

export default meta
type Story = StoryObj<typeof Icon>

// Basic example with controls
export const Default: Story = {
  args: {
    icon: RocketIcon,
    color: 'blue',
    size: 24,
    hasBackground: false,
  },
  parameters: {
    docs: {
      description: {
        story: 'A basic icon that can be customized using the controls below.',
      },
      source: {
        code: `
// Example usage:
<Icon icon={RocketIcon} color="blue" size={24} />
<Icon icon={StarIcon} color="yellow" size={16} hasBackground={true} />
<Icon icon={BellIcon} color="red" size={32} />
<Icon icon={HeartIcon} color="pink" size={48} hasBackground={true} />
`,
      },
    },
  },
}
