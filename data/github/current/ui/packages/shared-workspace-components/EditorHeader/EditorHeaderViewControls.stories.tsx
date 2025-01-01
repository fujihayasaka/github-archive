import type {Meta} from '@storybook/react'
import {EditorHeaderViewControls} from './EditorHeaderViewControls'
import {noop} from '@github-ui/noop'

const meta: Meta = {
  title: 'Recipes/EditorHeaderViewControls',
  component: EditorHeaderViewControls,
  args: {
    isDeleted: false,
    isPreviewable: true,
    updateEditorMode: noop,
  },
}

export default meta

export const Example = {}
