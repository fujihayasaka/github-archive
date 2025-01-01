import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'

import {WorkbenchUIContext, type WorkbenchUIContextData} from '../WorkbenchUIContext'

export const workbenchUIContextDecoratorArgTypes = {
  createRepositoryModelOpen: {
    control: 'boolean',
    table: {
      category: 'WorkbenchUIContext',
    },
  },
  mobileViewActive: {
    control: 'boolean',
    table: {
      category: 'WorkbenchUIContext',
    },
  },
  previewBrowserRef: {
    control: 'boolean',
    table: {
      category: 'WorkbenchUIContext',
    },
  },
  previewRefreshing: {
    control: 'boolean',
    table: {
      category: 'WorkbenchUIContext',
    },
  },
  previewUrl: {
    control: 'boolean',
    table: {
      category: 'WorkbenchUIContext',
    },
  },
  sidePanelOpen: {
    control: 'boolean',
    table: {
      category: 'WorkbenchUIContext',
    },
  },
  workingMode: {
    control: 'select',
    options: ['code', 'preview', 'split'],
    table: {
      category: 'WorkbenchUIContext',
    },
  },
}

export const workbenchUIContextDecoratorArgs = {
  createRepositoryModelOpen: false,
  mobileViewActive: false,
  previewBrowserRef: {current: null},
  previewRefreshing: false,
  previewUrl: null,
  sidePanelOpen: false,
  workingMode: 'split',
}

export const withWorkbenchUIContext: Decorator = (Story, {args}) => {
  const contextValue = {
    createRepositoryModelOpen: args.isFullscreen,
    setCreateRepositoryModelOpen: action('setCreateRepositoryModelOpen'),
    mobileViewActive: args.mobileViewActive,
    previewBrowserRef: args.previewBrowserRef,
    previewRefreshing: args.previewRefreshing,
    previewUrl: args.previewUrl,
    refreshPreview: action('refreshPreview'),
    setIsFullscreen: action('setIsFullscreen'),
    setMobileViewActive: action('setMobileViewActive'),
    setPreviewUrl: action('setPreviewUrl'),
    setWorkingMode: action('setWorkingMode'),
    sidePanelOpen: args.sidePanelOpen,
    toggleSidePanel: action('toggleSidePanel'),
    workingMode: args.workingMode,
  } as WorkbenchUIContextData

  return (
    <WorkbenchUIContext.Provider value={contextValue}>
      <Story />
    </WorkbenchUIContext.Provider>
  )
}
