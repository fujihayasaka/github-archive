import type {ArgTypes, Meta} from '@storybook/react'

import {withCodespaceContext} from '../../../contexts/.storybook/WithCodespaceContext'
import {filesContextDecoratorArgTypes, withFilesContext} from '../../../contexts/.storybook/WithFilesContext'
import {
  fileSyncerContextDecoratorArgs,
  fileSyncerContextDecoratorArgTypes,
  withFileSyncerContext,
} from '../../../contexts/.storybook/WithFileSyncerContext'
import {withRoutePayload} from '../../../contexts/.storybook/WithRoutePayload'
import {
  withWorkbenchContext,
  workbenchContextDecoratorArgs,
  workbenchContextDecoratorArgTypes,
} from '../../../contexts/.storybook/WithWorkbenchContext'
import {
  withWorkbenchStoreContext,
  workbenchStoreContextDecoratorArgs,
  workbenchStoreContextDecoratorArgTypes,
} from '../../../contexts/.storybook/WithWorkbenchStoreContext'
import type {FileEntry} from '../../../types/file-syncer-v2-types'
import {AiPanel, type AiPanelProps} from './AiPanel'

const aiPanelArgs = {
  isFetching: false,
  workbenchId: '12345',
}

const aiPanelArgTypes: ArgTypes<AiPanelProps> = {
  isFetching: {
    control: 'boolean',
    description: 'If the workbench is fetching data from the agent',
    table: {
      defaultValue: {summary: aiPanelArgs.isFetching.toString()},
      category: 'AiPanel',
    },
  },
  workbenchId: {
    control: 'text',
    description: 'The ID of the current workbench',
    table: {
      defaultValue: {summary: aiPanelArgs.workbenchId},
      category: 'AiPanel',
    },
  },
}

export default {
  title: 'Apps/Workbench/Components/SidePanel/Panels/AiPanel',
  component: AiPanel,
  argTypes: {
    ...workbenchStoreContextDecoratorArgTypes,
    ...workbenchContextDecoratorArgTypes,
    ...fileSyncerContextDecoratorArgTypes,
    ...filesContextDecoratorArgTypes,
    ...aiPanelArgTypes,
  },
  args: {
    ...workbenchStoreContextDecoratorArgs,
    ...workbenchContextDecoratorArgs,
    ...fileSyncerContextDecoratorArgs,
    ...aiPanelArgs,
  },
  decorators: [
    withWorkbenchStoreContext,
    withWorkbenchContext,
    withFileSyncerContext,
    withFilesContext,
    withCodespaceContext,
    withRoutePayload,
    Story => (
      <div className="width-full d-flex flex-justify-center">
        <div style={{width: 420}}>
          <Story />
        </div>
      </div>
    ),
  ],
} satisfies Meta<typeof AiPanel>

export const Empty = {
  args: {
    isFetching: false,
    getFileSyncerV2: () => null,
  },
}

export const Loading = {
  args: {
    getFileList: () => fileEntries,
    getFileSyncerV2: () => ({
      readFileString: async (path: string) => {
        await asyncTimeout(60 * 1000) // delay file fetching for 1 minute to show loading state
        return `//${path}\nconst prompt = spark.llmPrompt\`this is a prompt\`\n// this is a prompt file`
      },
    }),
  },
}

export const Populated = {
  args: {
    getFileList: () => fileEntries,
    getFileSyncerV2: () => ({
      readFileString: async () => {
        await asyncTimeout(250)
        return 'spark.llmPrompt`this is a prompt`\n// this is a prompt file'
      },
    }),
  },
}

const asyncTimeout = (ms: number): Promise<NodeJS.Timeout> => new Promise(resolve => setTimeout(resolve, ms))

const fileEntries: FileEntry[] = [
  {type: 'file', path: 'file1.ts'},
  {type: 'file', path: 'file2.tsx'},
]
