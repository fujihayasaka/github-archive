import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {ReactQueryDevtools} from '@tanstack/react-query-devtools'
import {http, HttpResponse} from 'msw'

import {mockWorkbench} from '../__tests__/workbench-mocks'
import {
  codespaceContextDecoratorArgs,
  codespaceContextDecoratorArgTypes,
  withCodespaceContext,
} from '../contexts/.storybook/WithCodespaceContext'
import {
  ContentFilterDecoratorArgs,
  ContentFilterDecoratorArgTypes,
  withContentFilter,
} from '../contexts/.storybook/WithContentFilterContext'
import {withEditorContext} from '../contexts/.storybook/WithEditorContext'
import {withErrorsContext} from '../contexts/.storybook/WithErrorsContext'
import {filesContextDecoratorArgTypes, withFilesContext} from '../contexts/.storybook/WithFilesContext'
import {
  fileSyncerContextDecoratorArgs,
  fileSyncerContextDecoratorArgTypes,
  withFileSyncerContext,
} from '../contexts/.storybook/WithFileSyncerContext'
import {
  IterationHistoryContextDecoratorArgs,
  IterationHistoryContextDecoratorArgTypes,
  withIterationHistoryContext,
} from '../contexts/.storybook/WithIterationHistoryContext'
import {withPublishingContext} from '../contexts/.storybook/WithPublishingContext'
import {
  RoutePayloadDecoratorArgs,
  RoutePayloadDecoratorArgTypes,
  withRoutePayload,
} from '../contexts/.storybook/WithRoutePayload'
import {withServerEventsContext} from '../contexts/.storybook/WithServerEventsContext'
import {
  TargetedEditsContextDecoratorArgs,
  TargetedEditsContextDecoratorArgTypes,
  withTargetedEditsContext,
} from '../contexts/.storybook/WithTargetedEditsContext'
import {
  terminalContextDecoratorArgs,
  terminalContextDecoratorArgTypes,
  withTerminalContext,
} from '../contexts/.storybook/WithTerminalContext'
import {withUserPromptContext} from '../contexts/.storybook/WithUserPromptContext'
import {
  withWorkbenchContext,
  workbenchContextDecoratorArgs,
  workbenchContextDecoratorArgTypes,
} from '../contexts/.storybook/WithWorkbenchContext'
import {withWorkbenchEditorAppContext} from '../contexts/.storybook/WithWorkbenchEditorAppContext'
import {
  withWorkbenchPreviewContext,
  WorkbenchPreviewDecoratorArgs,
  WorkbenchPreviewDecoratorArgTypes,
} from '../contexts/.storybook/WithWorkbenchPreviewContext'
import {
  withWorkbenchStoreContext,
  workbenchStoreContextDecoratorArgs,
  workbenchStoreContextDecoratorArgTypes,
} from '../contexts/.storybook/WithWorkbenchStoreContext'
import {
  withWorkspaceEditorUIContext,
  workspaceEditorUIContextDecoratorArgs,
  workspaceEditorUIContextDecoratorArgTypes,
} from '../contexts/.storybook/WithWorkspaceEditorUIContext'
import {WorkbenchUIContextProvider} from '../contexts/WorkbenchUIContext'
import {withAnalyticsContext} from '../telemetry/.storybook/WithAnalyticsContext'
import type {FileEntry} from '../types/file-syncer-v2-types'
import {Workbench} from './Workbench'

const ASYNC_DELAY = 250

export default {
  title: 'Apps/Workbench/Routes/Workbench',
  component: Workbench,
  argTypes: {
    ...RoutePayloadDecoratorArgTypes,
    ...TargetedEditsContextDecoratorArgTypes,
    ...workbenchContextDecoratorArgTypes,
    ...workspaceEditorUIContextDecoratorArgTypes,
    ...workbenchStoreContextDecoratorArgTypes,
    ...codespaceContextDecoratorArgTypes,
    ...fileSyncerContextDecoratorArgTypes,
    ...filesContextDecoratorArgTypes,
    ...terminalContextDecoratorArgTypes,
    ...WorkbenchPreviewDecoratorArgTypes,
    ...IterationHistoryContextDecoratorArgTypes,
    ...ContentFilterDecoratorArgTypes,
    workbenchData: {table: {disable: true}},
    copilotCurrentTopic: {table: {disable: true}},
  },
  args: {
    ...RoutePayloadDecoratorArgs,
    ...TargetedEditsContextDecoratorArgs,
    ...workbenchStoreContextDecoratorArgs,
    ...workbenchContextDecoratorArgs,
    ...workspaceEditorUIContextDecoratorArgs,
    ...codespaceContextDecoratorArgs,
    ...fileSyncerContextDecoratorArgs,
    ...terminalContextDecoratorArgs,
    ...WorkbenchPreviewDecoratorArgs,
    ...IterationHistoryContextDecoratorArgs,
    ...ContentFilterDecoratorArgs,
    workbenchData: undefined,
    copilotCurrentTopic: undefined,
  },
  decorators: [
    Story => (
      <>
        <ReactQueryDevtools buttonPosition="bottom-right" />
        <Story />
      </>
    ),
    withErrorsContext,
    withPublishingContext,
    withServerEventsContext,
    // real provider passed to allow for navigating the UI
    Story => (
      <WorkbenchUIContextProvider>
        <Story />
      </WorkbenchUIContextProvider>
    ),
    withContentFilter,
    withIterationHistoryContext,
    withTargetedEditsContext,
    withWorkbenchPreviewContext,
    withTerminalContext,
    withEditorContext,
    withFilesContext,
    withFileSyncerContext,
    withCodespaceContext,
    withWorkspaceEditorUIContext,
    withWorkbenchContext,
    withWorkbenchStoreContext,
    withWorkbenchEditorAppContext,
    withUserPromptContext,
    withRoutePayload,
    withAnalyticsContext,
  ],
  parameters: {
    enabledFeatures: ['copilot_workbench_debug_panel'],
    a11y: disableA11yRuleForDialog,
    msw: {
      handlers: [
        http.get(`/copilot/spark/workbench.json`, async () => {
          await asyncTimeout(ASYNC_DELAY)
          return HttpResponse.json(
            {
              workbenches: [mockWorkbench],
            },
            {status: 200},
          )
        }),
        http.get(`/copilot/spark/workbench`, async () => {
          await asyncTimeout(ASYNC_DELAY)
          return HttpResponse.json(
            {
              workbenches: [mockWorkbench],
            },
            {status: 200},
          )
        }),
        http.post(`https://mycodespace-5000.domain/auth/postback/tunnel`, async () => {
          await asyncTimeout(ASYNC_DELAY)
          return HttpResponse.json({}, {status: 302, type: 'opaqueredirect'})
        }),
        http.post('/github-copilot/chat/token', async () => {
          await asyncTimeout(ASYNC_DELAY)
          return HttpResponse.json({}, {status: 200})
        }),
        http.get('https://mycodespace-9000.domain/prompts', async () => {
          await asyncTimeout(ASYNC_DELAY)
          return HttpResponse.json(
            {
              data: {
                status: '200',
                prompts: [
                  {
                    file: 'file.txt',
                    description: 'this is a static file',
                    uniqueFileId: 'file.txt',
                  },
                  {
                    file: `file${Math.floor(Math.random() * 100)}.txt`,
                    description: 'this is a randomly-named file per request',
                    uniqueFileId: `file${Math.floor(Math.random() * 100)}.txt`,
                  },
                ],
              },
            },
            {
              status: 200,
            },
          )
        }),
      ],
    },
  },
} satisfies Meta<typeof Workbench>

export const Loaded = {
  args: {
    getFileList: () => fileEntries,
    getFileSyncerV2: () => ({
      readFileString: async () => {
        await asyncTimeout(250)
        return 'const prompt = spark.llmPrompt`this is a prompt`\n\nreturn null;'
      },
    }),
  },
}

export const Generating = {
  args: {
    ...Loaded.args,
    isFetching: true,
  },
}

export const CodespaceLoading = {
  args: {
    ...Loaded.args,
    codespaceState: 'starting',
    codespaceStatus: 'starting',
  },
}

export const CodespaceFailed = {
  args: {
    ...Loaded.args,
    codespaceState: 'failed',
    codespaceStatus: 'error',
  },
}

const asyncTimeout = (ms: number): Promise<NodeJS.Timeout> => new Promise(resolve => setTimeout(resolve, ms))

const fileEntries: FileEntry[] = [
  {type: 'file', path: 'file1.ts'},
  {type: 'file', path: 'file2.tsx'},
]
