import {EditorHeader} from './EditorHeader'
import type {Meta} from '@storybook/react'

import {noop} from '@github-ui/noop'

const meta: Meta = {
  title: 'Recipes/EditorHeader',
  component: EditorHeader,
  args: {
    isEditing: false,
    setIsEditing: noop,
    isNewFilePage: false,
    initialPath: 'path/to/file',
    path: 'path/to/file',
    onPathChange: noop,
    pathError: false,
    onSaveFileName: noop,
    onTerminalClick: noop,
    onDetailsClick: noop,
    isTreeExpanded: false,
    hasCodespaceInfo: false,
    codespaceState: 'none',
    codespacePermissionAccepted: true,
    isCodespaceRecoveryContainer: false,
    pollForCodespacePermissionsAccepted: noop,
    recreateCodespace: noop,
  },
}

export default meta

export const Example = {}
