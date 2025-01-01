import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {PickerHeaderContent} from './PickerHeaderContent'

const meta = {
  title: 'Recipes/FilterPicker/Components/PickerHeaderContent',
  component: PickerHeaderContent,
  decorators: [storyWrapper()],
  args: {
    dialogTitle: 'Title',
    onDismiss: () => {},
    onQueryExecuted: () => {},
    providers: [],
  },
} satisfies Meta<typeof PickerHeaderContent>

export default meta

export const Default = {}
