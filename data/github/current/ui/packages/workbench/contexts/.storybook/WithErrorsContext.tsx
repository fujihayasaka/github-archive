import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {ErrorsContext, type ErrorsContextType} from '../ErrorsContext'

export const withErrorsContext: Decorator = (Story, {args}) => {
  const contextValue = {
    editorErrors: [],
    setEditorErrors: action('setEditorErrors'),
    editorWarnings: [],
    setEditorWarnings: action('setEditorWarnings'),
    previewBuildErrors: [],
    previewRuntimeErrors: [],
    setPreviewRuntimeErrors: action('setPreviewRuntimeErrors'),
    deployBuildErrors: [],
    setDeployBuildErrors: action('setDeployBuildErrors'),
    panelErrors: [],
    allErrors: [],
    iterateErrors: [],
    overlayErrors: [],
  } satisfies ErrorsContextType

  return (
    <ErrorsContext.Provider value={contextValue}>
      <Story />
    </ErrorsContext.Provider>
  )
}

export const ErrorsContextDecoratorArgs = {}

export const ErrorsContextDecoratorArgTypes = {}
