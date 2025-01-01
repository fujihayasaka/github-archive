import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {WorkbenchEditorAppContext, type WorkbenchEditorAppContextData} from '../WorkbenchEditorAppContext'
import {BlobService} from '../../utilities/blob-service'

export const withWorkbenchEditorAppContext: Decorator = (Story, {args}) => {
  const contextValue = {
    blobService: {
      getBlob: action('getBlob'),
    } as unknown as BlobService,
  } satisfies WorkbenchEditorAppContextData

  return (
    <WorkbenchEditorAppContext.Provider value={contextValue}>
      <Story />
    </WorkbenchEditorAppContext.Provider>
  )
}

export const WorkbenchEditorAppContextDecoratorArgs = {}

export const WorkbenchEditorAppContextDecoratorArgTypes = {}
