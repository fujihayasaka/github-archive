import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'
import {BannerType} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

import {WorkspaceEditorUIContext} from '@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext'
import type {
  WorkspaceEditorUIAction,
  WorkspaceEditorUIState,
} from '@github-ui/workspace-editor/utilities/workspace-editor-ui-reducer'

type ContextType = {
  state: WorkspaceEditorUIState
  dispatch: React.Dispatch<WorkspaceEditorUIAction>
}

export const workspaceEditorUIContextDecoratorArgTypes = {
  state: {
    table: {
      disable: true,
    },
  },
  dispatch: {
    table: {
      disable: true,
    },
  },
  banner: {
    control: 'select',
    options: [undefined, ...Object.values(BannerType)],
    table: {
      category: 'WorkspaceEditorUIContext',
    },
  },
  diffStyle: {
    control: 'select',
    options: ['inline', 'split'],
    table: {
      category: 'WorkspaceEditorUIContext',
    },
  },
  rightPanel: {
    control: 'select',
    options: ['', 'Chat', 'Suggestions'],
    table: {
      category: 'WorkspaceEditorUIContext',
    },
  },
  showDiff: {
    control: 'boolean',
    table: {
      category: 'WorkspaceEditorUIContext',
    },
  },
}

export const workspaceEditorUIContextDecoratorArgs = {
  state: {
    banner: undefined,
    diffStyle: 'inline',
    rightPanel: '',
    showDiff: false,
  },
  dispatch: action('dispatch'),
}

export const withWorkspaceEditorUIContext: Decorator = (Story, {args}) => {
  const contextValue = {
    state: {
      banner: args.banner,
      diffStyle: args.diffStyle,
      rightPanel: args.rightPanel,
      showDiff: args.showDiff,
    },
    dispatch: action('WorkspaceEditorUIContext__dispatch')
  } as ContextType

  return (
    <WorkspaceEditorUIContext.Provider value={contextValue}>
      <Story />
    </WorkspaceEditorUIContext.Provider>
  )
}
