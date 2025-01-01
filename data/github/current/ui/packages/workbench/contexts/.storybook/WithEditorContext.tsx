import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {EditorContext} from '../EditorContext'

export const withEditorContext: Decorator = (Story, {args}) => {
  const contextValue = {
    refreshEditor: args.refreshEditor as boolean,
    setRefreshEditor: action('setRefreshEditor'),
    forceEditorRefresh: action('forceEditorRefresh'),
    isAnimating: args.isAnimating as boolean,
    setIsAnimating: action('setIsAnimating'),
    previousPath: args.previousPath as string,
    setPreviousPath: action('setPreviousPath'),
    isNavigating: args.isNavigating as boolean,
    watchingPath: args.watchingPath as string,
    setWatchingPath: action('setWatchingPath'),
  } satisfies EditorContext

  return (
    <EditorContext.Provider value={contextValue}>
      <Story />
    </EditorContext.Provider>
  )
}

export const EditorContextDecoratorArgs = {
  refreshEditor: false,
  isAnimating: false,
  previousPath: '',
  isNavigating: false,
  watchingPath: '',
}

export const EditorContextDecoratorArgTypes = {
  refreshEditor: {
    control: 'boolean',
    table: {
      defaultValue: {summary: EditorContextDecoratorArgs.refreshEditor.toString()},
      category: 'EditorContext',
    },
  },
  isAnimating: {
    control: 'boolean',
    table: {
      defaultValue: {summary: EditorContextDecoratorArgs.isAnimating.toString()},
      category: 'EditorContext',
    },
  },
  previousPath: {
    control: 'text',
    table: {
      defaultValue: {summary: EditorContextDecoratorArgs.previousPath},
      category: 'EditorContext',
    },
  },
  isNavigating: {
    control: 'boolean',
    table: {
      defaultValue: {summary: EditorContextDecoratorArgs.isNavigating.toString()},
      category: 'EditorContext',
    },
  },
  watchingPath: {
    control: 'text',
    table: {
      defaultValue: {summary: EditorContextDecoratorArgs.watchingPath},
      category: 'EditorContext',
    },
  },
}
