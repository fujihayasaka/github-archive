import {useMemo} from 'react'
import {action} from '@storybook/addon-actions'
import type {Decorator} from '@storybook/react'
import {FileSyncerContext, type FileSyncerContextData} from '../FileSyncerContext'

export const withFileSyncerContext: Decorator = (Story, {args}) => {
  const fileSyncerContextValue = useMemo(
    () =>
      ({
        lastEditStateStamp: args.lastEditStateStamp,
        forceContentRefresh: action('forceContentRefresh'),
        getFileSyncerV2: args.getFileSyncerV2 ?? action('getFileSyncerV2'),
        fileSyncerStarted: args.fileSyncerStarted,
        fileContentsRef: args.fileContentsRef,
        fileChangeStack: [],
      }) as unknown as FileSyncerContextData,
    [args.lastEditStateStamp, args.getFileSyncerV2, args.fileSyncerStarted, args.fileContentsRef],
  )

  return (
    <FileSyncerContext.Provider value={fileSyncerContextValue}>
      <Story />
    </FileSyncerContext.Provider>
  )
}

export const fileSyncerContextDecoratorArgs = {
  lastEditStateStamp: Date.now(),
  fileSyncerStarted: true,
  fileContentsRef: {current: {}},
}

export const fileSyncerContextDecoratorArgTypes = {
  forceContentRefresh: {table: {disable: true}},
  getFileSyncerV2: {table: {disable: true}},
  fileContentsRef: {
    control: 'object',
    table: {
      defaultValue: {summary: fileSyncerContextDecoratorArgs.fileContentsRef},
      category: 'FileSyncerContext',
    },
  },
  lastEditStateStamp: {
    control: 'number',
    description: 'A timestamp representing the last edit',
    table: {
      defaultValue: {summary: fileSyncerContextDecoratorArgs.lastEditStateStamp},
      category: 'FileSyncerContext',
    },
  },
  fileSyncerStarted: {
    control: 'boolean',
    description: 'Indicates if the file syncer has started',
    table: {
      defaultValue: {summary: fileSyncerContextDecoratorArgs.fileSyncerStarted},
      category: 'FileSyncerContext',
    },
  },
}
