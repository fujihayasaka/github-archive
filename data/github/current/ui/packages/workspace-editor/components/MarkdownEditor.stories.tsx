import {CurrentRepositoryProvider, type Repository} from '@github-ui/current-repository'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'

import {CurrentPullRequestProvider} from '../contexts/CurrentPullRequestProvider'
import {getWorkspaceEditorRoutePayload} from '../test-utils/mock-data'
import {MarkdownEditor} from './MarkdownEditor'

const routePayload = getWorkspaceEditorRoutePayload()

const mockRepo: Repository = {
  ownerLogin: 'github',
  name: 'github',
  id: 123,
  defaultBranch: 'main',
  createdAt: '2020-01-01T00:00:00Z',
  currentUserCanPush: true,
  isFork: false,
  isEmpty: false,
  ownerAvatar: 'https://avatars.githubusercontent.com/u/9919?v=4',
  public: true,
  private: false,
  isOrgOwned: false,
  databaseId: 123456,
  nameWithOwner: 'github/github',
}

const meta: Meta<typeof MarkdownEditor> = {
  title: 'Apps/Workspace Editor/Components/MarkdownEditor',
  component: MarkdownEditor,
  parameters: {
    docs: {
      description: {
        component: 'An editor component for Markdown content.',
      },
    },
  },
  decorators: [
    Story => (
      <CurrentRepositoryProvider repository={mockRepo}>
        <CurrentPullRequestProvider>
          <Story />
        </CurrentPullRequestProvider>
      </CurrentRepositoryProvider>
    ),
    storyWrapper({routePayload}),
  ],
}

export default meta

type Story = StoryObj<typeof MarkdownEditor>

export const Default: Story = {
  name: 'Markdown Editor',
  args: {
    editorMode: 2,
    showDiff: false,
    height: '400px',
    saveChanges: () => {},
    diffEditorSettings: {
      original: '# Original Markdown\n\nThis is the original content.',
      modified: '# Modified Markdown\n\nThis is the modified content.',
    },
    editorSettings: {
      value: '# Hello, Markdown!\n\nThis is a simple markdown editor example.',
    },
  },
}
