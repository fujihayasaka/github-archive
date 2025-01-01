import type {Meta} from '@storybook/react'
import {TimelineDivider} from './TimelineDivider'

const args = {
  isLoading: false,
  isHovered: false,
  large: true,
  id: 'timeline-divider',
}

const meta = {
  title: 'TimelineEvents/TimelineDivider',
  component: TimelineDivider,
} satisfies Meta<typeof TimelineDivider>

export default meta

export const Example = {args}
