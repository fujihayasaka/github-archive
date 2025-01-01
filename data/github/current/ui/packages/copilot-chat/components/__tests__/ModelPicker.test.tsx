import {render} from '@github-ui/react-core/test-utils'
import {ThemeProvider} from '@primer/react'
import {screen} from '@testing-library/react'

import {getCopilotChatProviderProps, getDefaultReducerState} from '../../test-utils/mock-data'
import {setupResizeObserverMock} from '../../test-utils/mock-resize-observer'
import type {CopilotChatMessage, CopilotChatModel, CopilotModelPolicyState} from '../../utils/copilot-chat-types'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {ModelPicker} from '../ModelPicker'

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
      vision: true,
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

const fetchModels = jest.fn()
const selectModel = jest.fn()
jest.mock('../../utils/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('../../utils/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        fetchModels,
        selectModel,
      }
    },
  }
})

beforeEach(() => {
  setupResizeObserverMock()
})
afterEach(() => {
  jest.resetAllMocks()
})

const promiseNoop = () => Promise.resolve()

describe('ModelPicker', () => {
  it('given a single model, should not render the model picker', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT],
          model: DEFAULT,
        }}
      >
        <ModelPicker onNewThreadSelected={promiseNoop} />
      </CopilotChatProvider>,
    )

    expect(screen.queryByText(DEFAULT.displayName)).not.toBeInTheDocument()
  })

  it('given multiple models, should render the model picker', () => {
    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT, ADDITIONAL],
          model: DEFAULT,
        }}
      >
        <ModelPicker onNewThreadSelected={promiseNoop} />
      </CopilotChatProvider>,
    )

    expect(screen.getByText(DEFAULT.displayName)).toBeInTheDocument()
  })

  it('renders the selector when clicked upon', async () => {
    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )
    const button = screen.getByRole('button')
    await user.click(button)
    expect(screen.getByText(ADDITIONAL.displayName)).toBeInTheDocument()
  })

  it('with third party models present, renders vendor logos', async () => {
    const THIRD_PARTY = {
      ...ADDITIONAL,
      id: 'three',
      isThirdParty: true,
      vendor: 'Third Party',
      logoURL: 'https://example.com/logo.png',
    }
    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL, THIRD_PARTY],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )
    const button = screen.getByRole('button')
    await user.click(button)
    expect(screen.getByAltText(`${THIRD_PARTY.vendor} logo`)).toBeInTheDocument()
  })

  it('with no third party models present, does not render vendor logos', async () => {
    const DEFAULT_WITH_LOGO = {
      ...DEFAULT,
      logoURL: 'https://example.com/logo.png',
    }
    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT_WITH_LOGO, ADDITIONAL],
            model: DEFAULT_WITH_LOGO,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )
    const button = screen.getByRole('button')
    await user.click(button)
    expect(screen.queryByAltText(`${DEFAULT_WITH_LOGO.vendor} logo`)).not.toBeInTheDocument()
  })

  it('changes the selected model', async () => {
    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )
    expect(screen.getByText(DEFAULT.displayName)).toBeInTheDocument()
    expect(screen.queryByText(ADDITIONAL.displayName)).not.toBeInTheDocument()

    const button = screen.getByRole('button')
    await user.click(button)

    const modelSelector = screen.getByText(ADDITIONAL.displayName)
    await user.click(modelSelector)

    expect(selectModel).toHaveBeenCalledWith(ADDITIONAL)
  })

  it('switching requires confirmation if policy is not enabled', async () => {
    const state: CopilotModelPolicyState = 'unconfigured'
    const REQUIRES_CONFIRMATION = {
      ...ADDITIONAL,
      policy: {
        state,
        terms: 'You must accept',
      },
    }

    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, REQUIRES_CONFIRMATION],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )

    const button = screen.getByRole('button')
    await user.click(button)
    const modelSelector = screen.getByText(REQUIRES_CONFIRMATION.displayName)
    await user.click(modelSelector)

    expect(screen.getByText(`Enable ${REQUIRES_CONFIRMATION.displayName}`)).toBeInTheDocument()
  })

  it('switching requires a new conversation if the thread has tool calls and the model does not support it', async () => {
    const NO_TOOL_CALL_SUPPORT = {
      ...ADDITIONAL,
      isThirdParty: false,
      capabilities: {
        ...ADDITIONAL.capabilities,
        supports: {
          ...ADDITIONAL.capabilities.supports,
          // eslint-disable-next-line camelcase
          tool_calls: false,
        },
      },
    }
    const messages: CopilotChatMessage[] = [
      {
        skillExecutions: [{slug: 'test-skill', status: 'completed'}],
        id: '',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
      },
    ]

    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, NO_TOOL_CALL_SUPPORT],
            model: DEFAULT,
            messages,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )

    const button = screen.getByRole('button')
    await user.click(button)
    const modelSelector = screen.getByText(NO_TOOL_CALL_SUPPORT.displayName)
    await user.click(modelSelector)

    expect(screen.getByText(`New conversation`)).toBeInTheDocument()
    expect(screen.getByText(`Switch model`)).toBeInTheDocument()
  })

  it('switching requires a new conversation if the thread has media content and the model does not support it', async () => {
    const NO_VISION_SUPPORT = {
      ...ADDITIONAL,
      isThirdParty: false,
      capabilities: {
        ...ADDITIONAL.capabilities,
        supports: {
          ...ADDITIONAL.capabilities.supports,
          vision: false,
        },
      },
    }
    const messages: CopilotChatMessage[] = [
      {
        id: '',
        role: 'user',
        createdAt: '',
        threadID: '',
        references: null,
        mediaContent: [
          {
            mediaType: 'image/png',
            name: 'some image',
            url: 'https://example.com/image.png',
          },
        ],
      },
    ]

    const {user} = render(
      <ThemeProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, NO_VISION_SUPPORT],
            model: DEFAULT,
            messages,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </CopilotChatProvider>
      </ThemeProvider>,
    )

    const button = screen.getByRole('button')
    await user.click(button)
    const modelSelector = screen.getByText(NO_VISION_SUPPORT.displayName)
    await user.click(modelSelector)

    expect(screen.getByText(`New conversation`)).toBeInTheDocument()
    expect(screen.getByText(`Switch model`)).toBeInTheDocument()
  })
})
