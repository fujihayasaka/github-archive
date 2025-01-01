import {useMemo} from 'react'
import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'
import {WorkbenchContext, type WorkbenchContextData} from '../WorkbenchContext'

export const withWorkbenchContext: Decorator = (Story, {args}) => {
  const workbenchContextValue = useMemo(
    () =>
      ({
        id: '12345',
        isFetching: args.isFetching,
        friendlyName: args.friendlyName,
        name: args.friendlyName,
        initialPromptSubmitted: {current: args.initialPromptSubmitted},
        fileContentsRef: args.fileContentsRef,
        setIsMobileSidebarOpen: action('setIsMobileSidebarOpen'),
        setFilterSuggestions: action('setFilterSuggestions'),
        setIsFetching: action('setIsFetching'),
        setIsLoadingFromModel: action('setIsLoadingFromModel'),
        setIterationStartTime: action('setIterationStartTime'),
        setIsOptimisticLoading: action('setIsOptimisticLoading'),
        sparkFileUrl: action('sparkFileUrl'),
      }) as unknown as WorkbenchContextData,
    [args.isFetching, args.friendlyName, args.initialPromptSubmitted, args.fileContentsRef],
  )

  return (
    <WorkbenchContext.Provider value={workbenchContextValue}>
      <Story />
    </WorkbenchContext.Provider>
  )
}

export const workbenchContextDecoratorArgs = {
  isFetching: false,
  friendlyName: 'friendly-name',
  fileContentsRef: {current: {}},
  initialPromptSubmitted: true,
}

export const workbenchContextDecoratorArgTypes = {
  isFetching: {
    control: 'boolean',
    table: {
      category: 'WorkbenchContext',
    },
  },
  friendlyName: {
    control: 'text',
    description: 'The friendly name of the workbench',
    table: {
      defaultValue: {summary: workbenchContextDecoratorArgs.friendlyName},
      category: 'WorkbenchStoreContext',
    },
  },
  initialPromptSubmitted: {
    control: 'boolean',
    table: {
      category: 'WorkbenchContext',
    },
  },
  fileContentsRef: {table: {disable: true}},
}
