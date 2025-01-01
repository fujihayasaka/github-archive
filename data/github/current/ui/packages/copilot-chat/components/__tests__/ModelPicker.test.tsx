import {render} from '@github-ui/react-core/test-utils'
import {ThemeProvider} from '@primer/react'
import {screen} from '@testing-library/react'

import {getCopilotChatProviderProps, getDefaultReducerState} from '../../test-utils/mock-data'
import {setupResizeObserverMock} from '../../test-utils/mock-resize-observer'
import {
  type CopilotChatMessage,
  type CopilotChatModel,
  type CopilotChatPayload,
  CopilotLicenseType,
  type CopilotModelPolicyState,
  CopilotPlan,
} from '../../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {ModelPicker} from '../ModelPicker'
import {EntitlementContext} from '../quota/EntitlementContext'

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

const ENTITLEMENT_CONTEXT_VALUE = {
  plan: CopilotPlan.IndividualPro,
  licenseType: CopilotLicenseType.LicensedFull,
  chatQuotaRemaining: 100,
  premiumChatQuotaRemaining: 100,
  resetDate: '02/21/1991',
  isLicensedLimited: false,
  chatQuotaExceeded: false,
  premiumInteractionsQuotaExceeded: false,
  reloadQuota: jest.fn(),
  canPurchaseAdditionalQuota: false,
  canUpgradePlan: false,
  overagesEnabled: false,
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

  it('defaults to the chat_default model', () => {
    // eslint-disable-next-line camelcase
    const chatDefaultModel = {...ADDITIONAL, is_chat_default: true}

    render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT, chatDefaultModel],
          model: DEFAULT,
          modelsLoading: {
            state: 'loaded',
            error: null,
          },
        }}
      >
        <EntitlementContext.Provider value={{...ENTITLEMENT_CONTEXT_VALUE}}>
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </EntitlementContext.Provider>
      </CopilotChatProvider>,
    )

    expect(selectModel).toHaveBeenCalledWith(chatDefaultModel, true)
  })

  it('defaults to the chat_fallback model if premiumRequestQuotasEnabled flag is set and quota is exhausted', async () => {
    jest.spyOn(copilotFeatureFlags, 'premiumRequestQuotasEnabled', 'get').mockReturnValue(true)
    // eslint-disable-next-line camelcase
    const chatDefaultModel = {...ADDITIONAL, is_chat_default: true}
    // eslint-disable-next-line camelcase
    const chatFallbackModel = {...ADDITIONAL, id: 'fallback', displayName: 'Two Model (Base)', is_chat_fallback: true}

    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT, chatDefaultModel, chatFallbackModel],
          model: DEFAULT,
          modelsLoading: {
            state: 'loaded',
            error: null,
          },
        }}
      >
        <EntitlementContext.Provider value={{...ENTITLEMENT_CONTEXT_VALUE, premiumInteractionsQuotaExceeded: true}}>
          <ModelPicker onNewThreadSelected={promiseNoop} />
        </EntitlementContext.Provider>
      </CopilotChatProvider>,
    )

    expect(selectModel).toHaveBeenCalledWith(chatFallbackModel, true)

    const button = screen.getByRole('button')
    await user.click(button)

    expect(screen.queryByText(chatFallbackModel.displayName)).not.toBeInTheDocument() // Ensure we don't render the fallback model with "(Base)" suffix
    expect(screen.getAllByText('Two Model')).toHaveLength(2) // Ensure the fallback model is selected and listed in the model picker
  })

  it('given multiple models with billing multipliers, should render the model picker with categories', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveStructuredModelPicker', 'get').mockReturnValue(true)
    const DEFAULT_WITH_BILLING = {
      ...DEFAULT,
      billing: {
        multiplier: 1,
        // eslint-disable-next-line camelcase
        is_premium: true,
      },
    }
    const ADDITIONAL_WITH_BILLING = {
      ...ADDITIONAL,
      billing: {
        multiplier: 2,
        // eslint-disable-next-line camelcase
        is_premium: true,
      },
    }
    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT_WITH_BILLING, ADDITIONAL_WITH_BILLING],
          model: DEFAULT_WITH_BILLING,
        }}
      >
        <ModelPicker onNewThreadSelected={promiseNoop} />
      </CopilotChatProvider>,
    )

    const button = screen.getByRole('button')
    await user.click(button)

    expect(screen.queryAllByText(DEFAULT_WITH_BILLING.displayName)).toHaveLength(2)
    expect(screen.getByText(ADDITIONAL_WITH_BILLING.displayName)).toBeInTheDocument()
    expect(screen.getByText('Versatile and highly intelligent')).toBeInTheDocument()
  })

  it('given multiple models with all the same billing multipliers, should render the model picker without categories', async () => {
    jest.spyOn(copilotFeatureFlags, 'immersiveStructuredModelPicker', 'get').mockReturnValue(true)
    const DEFAULT_WITH_BILLING = {
      ...DEFAULT,
      billing: {
        multiplier: 1,
        // eslint-disable-next-line camelcase
        is_premium: true,
      },
    }
    const ADDITIONAL_WITH_BILLING = {
      ...ADDITIONAL,
      billing: {
        multiplier: 1,
        // eslint-disable-next-line camelcase
        is_premium: true,
      },
    }
    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT_WITH_BILLING, ADDITIONAL_WITH_BILLING],
          model: DEFAULT_WITH_BILLING,
        }}
      >
        <ModelPicker onNewThreadSelected={promiseNoop} />
      </CopilotChatProvider>,
    )

    const button = screen.getByRole('button')
    await user.click(button)

    expect(screen.queryAllByText(DEFAULT_WITH_BILLING.displayName)).toHaveLength(2)
    expect(screen.getByText(ADDITIONAL_WITH_BILLING.displayName)).toBeInTheDocument()
    expect(screen.queryByText('Versatile and highly intelligent')).not.toBeInTheDocument()
  })

  it('given multiple models, for free users should show upsell models', async () => {
    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        copilotChatPayload={{licenseType: CopilotLicenseType.LicensedLimited} as CopilotChatPayload}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          availableModels: [DEFAULT, ADDITIONAL],
          model: DEFAULT,
        }}
      >
        <ModelPicker onNewThreadSelected={promiseNoop} limited />
      </CopilotChatProvider>,
    )
    const button = screen.getByRole('button')
    await user.click(button)

    expect(screen.queryAllByText('Upgrade')).toHaveLength(2)
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

  describe('when type message-retry', () => {
    it('renders a retry button and a dropdown button instead of model name', () => {
      render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} type={'message-retry'} />
        </CopilotChatProvider>,
      )

      expect(screen.queryByText(DEFAULT.displayName)).not.toBeInTheDocument()
      expect(screen.getByRole('button', {name: `Retry with ${DEFAULT.displayName}`})).toBeInTheDocument()
      expect(screen.getByRole('button', {name: `Retry with…`})).toBeInTheDocument()
    })

    it('allows retrying with the currently selected model from retry button', async () => {
      const {user} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} type={'message-retry'} selectedModel={ADDITIONAL} />
        </CopilotChatProvider>,
      )

      const button = screen.getByRole('button', {name: `Retry with ${ADDITIONAL.displayName}`})
      await user.click(button)

      expect(selectModel).toHaveBeenCalledWith(ADDITIONAL)
    })

    it('allows retrying with the currently selected model from the dropdown', async () => {
      const {user} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} type={'message-retry'} selectedModel={ADDITIONAL} />
        </CopilotChatProvider>,
      )

      const button = screen.getByRole('button', {name: `Retry with…`})
      await user.click(button)

      const modelSelectors = screen.queryAllByText(ADDITIONAL.displayName)
      expect(modelSelectors.length === 2).toBeTruthy()
      await user.click(modelSelectors[1]!)

      expect(selectModel).toHaveBeenCalledWith(ADDITIONAL)
    })

    it('shows a separate entry for the selectedModel', async () => {
      const {user} = render(
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('2', undefined, 'immersive'),
            availableModels: [DEFAULT, ADDITIONAL],
            model: DEFAULT,
          }}
        >
          <ModelPicker onNewThreadSelected={promiseNoop} type={'message-retry'} selectedModel={DEFAULT} />
        </CopilotChatProvider>,
      )

      const button = screen.getByRole('button', {name: `Retry with…`})
      await user.click(button)

      expect(screen.getByText('Try again')).toBeInTheDocument()
      const tryAgainSelector = screen.getByText('Try again')
      expect(tryAgainSelector).toBeInTheDocument()

      await user.click(tryAgainSelector)
      expect(selectModel).toHaveBeenCalledWith(DEFAULT)
    })
  })
})
