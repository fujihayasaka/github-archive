import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import FileResultsList from '../FileResultsList'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/FileResultsList',
  component: FileResultsList,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    commitOid: '1234',
    config: {
      enableOverlay: true,
    },
    findFileWorkerPath: 'mock',
    onRenderRow: undefined,
    onItemSelected: undefined,
    searchBoxRef: undefined,
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof FileResultsList>

export default meta

type Story = StoryObj<typeof FileResultsList>

export const Default: Story = {}
