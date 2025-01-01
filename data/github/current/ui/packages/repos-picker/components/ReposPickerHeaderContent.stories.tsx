import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {ReposPickerHeaderContent} from './ReposPickerHeaderContent'

const meta = {
  title: 'Recipes/ReposPicker/Components/ReposPickerHeaderContent',
  component: ReposPickerHeaderContent,
  decorators: [storyWrapper()],
  args: {
    dialogTitle: 'Title',
    onDismiss: noop,
    setQuery: noop,
  },
} satisfies Meta<typeof ReposPickerHeaderContent>

export default meta

export const Default = {}
