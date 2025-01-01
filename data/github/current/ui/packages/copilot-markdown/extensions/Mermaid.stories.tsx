import {MermaidRenderer} from './Mermaid'
import type {Meta, StoryFn} from '@storybook/react'

export default {
  title: 'Copilot/markdown/MermaidRenderer',
  component: MermaidRenderer,
  args: {
    code: `graph TD
    A[Start] --> B{Is it?}
    B -->|Yes| C[OK]
    C --> D[Rethink]
    D --> B
    B -->|No| E[End]`,
    identity: 'mermaid-example',
    viewscreenHost: 'fakeviewscreen-host',
  },
} satisfies Meta<typeof MermaidRenderer>

export const Default: StoryFn<typeof MermaidRenderer> = args => <MermaidRenderer {...args} />
Default.storyName = 'MermaidRenderer'
