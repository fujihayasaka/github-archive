import type {Meta, StoryObj} from '@storybook/react'

import {SharedMarkdownContent} from '../SharedMarkdownContent'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {currentRepositoryDecorator} from '../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/SharedMarkdownContent',
  component: SharedMarkdownContent,
  decorators: [currentRepositoryDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    onAnchorClick: () => {},
    richText: 'This is a test' as SafeHTMLString,
    stickyHeaderHeight: 0,
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof SharedMarkdownContent>

export default meta

type Story = StoryObj<typeof SharedMarkdownContent>

export const Default: Story = {}
