import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {TargetedEditsContext} from '../TargetedEditsContext'

export const withTargetedEditsContext: Decorator = (Story, {args}) => {
  const contextValue = {
    targetedEditsEnabled: args.targetedEditsEnabled as boolean,
    enableTargetedEdits: async () => {
      action('enableTargetedEdits')()
    },
    disableTargetedEdits: action('disableTargetedEdits'),
    toggleTargetedEdits: action('toggleTargetedEdits'),
    selectedElement: null,
    deselectElement: action('deselectElement'),
    modifyJsxClassName: async () => {
      action('modifyJsxClassName')()
    },
    modifyJsxText: async () => {
      action('modifyJsxText')()
    },
    modifyGlobalCssVariable: async () => {
      action('modifyGlobalCssVariable')()
    },
    modifyThemeVariables: async () => {
      action('modifyThemeVariables')()
    },
    refetchThemeVariables: (async () => {
      action('refetchThemeVariables')()
    }) as unknown as TargetedEditsContext['refetchThemeVariables'],
    themeVariables: undefined,
  } satisfies TargetedEditsContext

  return (
    <TargetedEditsContext.Provider value={contextValue}>
      <Story />
    </TargetedEditsContext.Provider>
  )
}

export const TargetedEditsContextDecoratorArgTypes = {
  targetedEditsEnabled: {
    control: 'boolean',
    description: 'Whether targeted edits are enabled',
    table: {
      category: 'TargetedEditsContext',
    },
  },
}

export const TargetedEditsContextDecoratorArgs = {
  targetedEditsEnabled: false,
}
