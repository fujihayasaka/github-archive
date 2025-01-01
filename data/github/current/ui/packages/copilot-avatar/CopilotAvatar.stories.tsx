import type {Meta, StoryObj} from '@storybook/react'

import {CopilotAvatar} from './CopilotAvatar'

/**
 * The CopilotAvatar component displays the GitHub Copilot icon that can be rendered
 * in different sizes and styles.
 */
const meta = {
  title: 'Copilot/CopilotAvatar',
  component: CopilotAvatar,
  parameters: {
    design: {
      type: 'figma',
      url: 'https://www.figma.com/design/cuXOGUqWdHI84LXwPtVWcL/Agents--Into-the-futureeeee?node-id=3616-235622&p=f&t=mqrKyJuoubG2AbLa-0',
    },
    controls: {expanded: true},
  },
  argTypes: {
    size: {
      options: ['small', 'medium', 'large'],
      control: {type: 'radio'},
      description: 'Controls the size of the avatar',
      table: {
        type: {summary: 'small | medium | large'},
        defaultValue: {summary: 'small'},
      },
    },
    minimal: {
      control: 'boolean',
      description: 'When true, removes the background color and box shadow',
      table: {
        type: {summary: 'boolean'},
        defaultValue: {summary: 'false'},
      },
    },
  },
  tags: ['autodocs'],
} satisfies Meta<typeof CopilotAvatar>

export default meta
type Story = StoryObj<typeof CopilotAvatar>

/**
 * Default appearance of the CopilotAvatar component with small size and default styling.
 */
export const Default: Story = {
  args: {
    size: 'small',
    minimal: false,
  },
}

/**
 * Medium sized CopilotAvatar.
 */
export const Medium: Story = {
  args: {
    size: 'medium',
    minimal: false,
  },
}

/**
 * Large sized CopilotAvatar.
 */
export const Large: Story = {
  args: {
    size: 'large',
    minimal: false,
  },
}

/**
 * Minimal appearance without background and shadow.
 */
export const Minimal: Story = {
  args: {
    size: 'large',
    minimal: true,
  },
}

/**
 * Shows all variants of the CopilotAvatar component side by side.
 */
export const AllVariants: StoryObj = {
  render: () => (
    <div style={{display: 'flex', flexDirection: 'column', gap: '2rem'}}>
      <div>
        <h3 style={{marginBottom: '1rem'}}>Default</h3>
        <div style={{display: 'flex', gap: '1.5rem', alignItems: 'center'}}>
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <p style={{marginBottom: '0.5rem'}}>Small</p>
            <CopilotAvatar size="small" />
          </div>
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <p style={{marginBottom: '0.5rem'}}>Medium</p>
            <CopilotAvatar size="medium" />
          </div>
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <p style={{marginBottom: '0.5rem'}}>Large</p>
            <CopilotAvatar size="large" />
          </div>
        </div>
      </div>
      <div>
        <h3 style={{marginBottom: '1rem'}}>Minimal</h3>
        <div style={{display: 'flex', gap: '1.5rem', alignItems: 'center'}}>
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <p style={{marginBottom: '0.5rem'}}>Small</p>
            <CopilotAvatar size="small" minimal />
          </div>
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <p style={{marginBottom: '0.5rem'}}>Medium</p>
            <CopilotAvatar size="medium" minimal />
          </div>
          <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <p style={{marginBottom: '0.5rem'}}>Large</p>
            <CopilotAvatar size="large" minimal />
          </div>
        </div>
      </div>
    </div>
  ),
}
