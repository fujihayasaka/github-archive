import {useMemo} from 'react'
import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'
import {FilesContext, type FilesContextData} from '../FilesContext'

export const withFilesContext: Decorator = (Story, {args}) => {
  const filesContextValue = useMemo(() => ({
    deleteFile: action('deleteFile'),
    editFile: action('editFile'),
    getFileList: args.getFileList ?? action('getFileList'),
  } as FilesContextData), [args.getFileList])

  return (
    <FilesContext.Provider value={filesContextValue}>
      <Story />
    </FilesContext.Provider>
  )
}

export const filesContextDecoratorArgTypes = {
  deleteFile: {table: {disable: true}},
  editFile: {table: {disable: true}},
  getFileList: {table: {disable: true}},
}
