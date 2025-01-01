import type {Meta, StoryObj} from '@storybook/react'
import {BrowserRouter} from 'react-router-dom'

import {getCopilotChatProviderProps, getDefaultReducerState} from '../test-utils/mock-data'
import type {CopilotChatModel} from '../utils/copilot-chat-types'
import {CopilotChatProvider} from '../utils/CopilotChatContext'
import {EntitlementProvider} from './quota/EntitlementContext'
import {RetryButton, type RetryButtonProps} from './RetryButton'

const meta = {
  title: 'Apps/Copilot/RetryButton',
  component: RetryButton,
  parameters: {},
  argTypes: {},
} satisfies Meta<RetryButtonProps>

export default meta

const DEFAULT: CopilotChatModel = {
  capabilities: {
    family: 'test-model-family',
    limits: {
      // eslint-disable-next-line camelcase
      max_prompt_tokens: 20000,
    },
    supports: {
      // eslint-disable-next-line camelcase
      parallel_tool_calls: true,
      // eslint-disable-next-line camelcase
      tool_calls: true,
    },
    tokenizer: 'o200k_base',
    type: 'chat',
  },
  id: 'one',
  name: 'First Model',
  version: 'fake-version-does-not-matter',
  displayName: 'One Model (Default)',
  preview: false,
  vendor: 'Azure OpenAI',
  hasLimitedCapabilities: false,
  isThirdParty: false,
  // eslint-disable-next-line camelcase
  model_picker_enabled: true,
}

const ADDITIONAL: CopilotChatModel = {
  capabilities: {
    family: 'test-model-family-two',
    limits: {
      // eslint-disable-next-line camelcase
      max_prompt_tokens: 20000,
    },
    supports: {
      // eslint-disable-next-line camelcase
      parallel_tool_calls: true,
      // eslint-disable-next-line camelcase
      tool_calls: true,
    },
    tokenizer: 'o200k_base',
    type: 'chat',
  },
  id: 'two',
  name: 'TWO',
  version: 'fake-version-does-not-matter',
  displayName: 'Two Model',
  preview: false,
  vendor: 'Azure OpenAI',
  hasLimitedCapabilities: false,
  isThirdParty: false,
  // eslint-disable-next-line camelcase
  model_picker_enabled: true,
}

export const Standalone: StoryObj<RetryButtonProps> = {
  render: () => (
    <EntitlementProvider initialLicenseType={'licensed_full'}>
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT, ADDITIONAL],
          model: DEFAULT,
        }}
      >
        <RetryButton
          handleRetryMessage={function (): void {
            alert('Clicked!')
          }}
        />
      </CopilotChatProvider>
    </EntitlementProvider>
  ),
}

export const RetryModel: StoryObj<RetryButtonProps> = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  render: () => (
    <BrowserRouter>
      <EntitlementProvider initialLicenseType={'licensed_full'}>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <RetryButton
            handleRetryMessage={function (): void {
              alert('Clicked!')
            }}
            showModelPicker
            navigateToNewThread={function (): Promise<void> {
              return Promise.resolve()
            }}
            model={DEFAULT}
          />
        </CopilotChatProvider>
      </EntitlementProvider>
    </BrowserRouter>
  ),
}
