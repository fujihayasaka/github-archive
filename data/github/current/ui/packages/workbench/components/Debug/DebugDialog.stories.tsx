import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {
  codespaceContextDecoratorArgs,
  codespaceContextDecoratorArgTypes,
  withCodespaceContext,
} from '../../contexts/.storybook/WithCodespaceContext'
import {
  databaseContextDecoratorArgs,
  databaseContextDecoratorArgTypes,
  withDatabaseContext,
} from '../../contexts/.storybook/WithDatabaseContext'
import {
  fileSyncerContextDecoratorArgs,
  fileSyncerContextDecoratorArgTypes,
  withFileSyncerContext,
} from '../../contexts/.storybook/WithFileSyncerContext'
import {
  IterationHistoryContextDecoratorArgs,
  IterationHistoryContextDecoratorArgTypes,
  withIterationHistoryContext,
} from '../../contexts/.storybook/WithIterationHistoryContext'
import {
  publishingContextDecoratorArgs,
  publishingContextDecoratorArgTypes,
  withPublishingContext,
} from '../../contexts/.storybook/WithPublishingContext'
import {
  RoutePayloadDecoratorArgs,
  RoutePayloadDecoratorArgTypes,
  withRoutePayload,
} from '../../contexts/.storybook/WithRoutePayload'
import {
  withWorkbenchPreviewContext,
  WorkbenchPreviewDecoratorArgs,
  WorkbenchPreviewDecoratorArgTypes,
} from '../../contexts/.storybook/WithWorkbenchPreviewContext'
import {DebugDialog, type DebugDialogProps} from './DebugDialog'

const debugDialogArgs = {
  onClose: () => {},
} satisfies Partial<DebugDialogProps>

const debugDialogArgTypes = {
  onClose: {
    table: {disable: true},
  },
}

export default {
  title: 'Apps/Workbench/Components/DebugDialog',
  component: DebugDialog,
  decorators: [
    withRoutePayload,
    withCodespaceContext,
    withWorkbenchPreviewContext,
    withFileSyncerContext,
    withPublishingContext,
    withIterationHistoryContext,
    withDatabaseContext,
  ],
  argTypes: {
    ...debugDialogArgTypes,
    ...RoutePayloadDecoratorArgTypes,
    ...codespaceContextDecoratorArgTypes,
    ...WorkbenchPreviewDecoratorArgTypes,
    ...fileSyncerContextDecoratorArgTypes,
    ...publishingContextDecoratorArgTypes,
    ...IterationHistoryContextDecoratorArgTypes,
    ...databaseContextDecoratorArgTypes,
  },
  args: {
    ...debugDialogArgs,
    ...RoutePayloadDecoratorArgs,
    ...codespaceContextDecoratorArgs,
    ...WorkbenchPreviewDecoratorArgs,
    ...fileSyncerContextDecoratorArgs,
    ...publishingContextDecoratorArgs,
    ...IterationHistoryContextDecoratorArgs,
    ...databaseContextDecoratorArgs,
  },
  parameters: {
    a11y: disableA11yRuleForDialog,
  },
} satisfies Meta<typeof DebugDialog>

export const Default = {
  args: {
    getFileSyncerV2: () => ({
      realFileString: async (path: string) => {
        const fileOutput = `These are the contents of the file at ${path}`
        return fileOutput
      },
    }),
  },
}
