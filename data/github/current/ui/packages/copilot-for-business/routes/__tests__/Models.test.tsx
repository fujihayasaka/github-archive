import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {makePoliciesRoutePayload} from '../../test-utils/mock-data'
import Models from '../Models'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const useCopilotSettingsMutationCommit = jest.fn(({onComplete}) => {
  onComplete({success: true})
})

jest.mock('../../hooks/use-fetchers', () => {
  const actual = jest.requireActual('../../hooks/use-fetchers')

  return {
    ...actual,
    useCreateMutator: jest.fn().mockImplementation(() => () => [useCopilotSettingsMutationCommit, false]),
  }
})

test('renders the index page', () => {
  render(<Models />, {routePayload: makePoliciesRoutePayload(), appPayload: makeFeatureFlags()})

  expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('GitHub Copilot models')
})

describe('business logic', () => {
  describe('managed by enterprise show link', () => {
    it('does not show when not managed by enterprise', () => {
      render(<Models />, {
        routePayload: makePoliciesRoutePayload({
          enterprise_name: null,
          enterprise_slug: null,
        }),
      })
      expect(screen.queryByTestId('cfb-managed-organization-enterprise')).not.toBeInTheDocument()
    })

    it('shows link to enterprise when managed by enterprise', () => {
      render(<Models />, {
        routePayload: makePoliciesRoutePayload({
          enterprise_name: 'Alena',
          enterprise_slug: 'alena',
        }),
      })
      const managedBy = screen.getByTestId('cfb-managed-organization-enterprise')
      expect(managedBy).toBeInTheDocument()
      expect(managedBy).toHaveTextContent(/Managed by Alena/)
    })
  })

  describe('data retention policies', () => {
    it('renders for Copilot for CLI and Copilot for dotcom', () => {
      render(<Models />, {
        routePayload: makePoliciesRoutePayload({
          copilot_for_dotcom: {
            configurable: true,
            visible: true,
          },
          cli: {
            configurable: true,
          },
        }),
      })
      const footnotes = screen.getByTestId('cb-policies-footnotes')
      expect(footnotes).toHaveTextContent(
        /Enabling Copilot in the CLI, Copilot in GitHub.com and Copilot Chat in GitHub Mobile will collect additional data and updated Product Terms apply. If preview features are enabled, you agree to pre-release terms/,
      )
    })

    it('does not render when on Copilot Enterprise plan', () => {
      render(<Models />, {
        routePayload: makePoliciesRoutePayload({
          copilot_for_dotcom: {
            configurable: true,
            visible: true,
          },
          cli: {
            configurable: true,
          },
          copilot_plan: 'enterprise',
        }),
      })
      const footnotes = screen.getByTestId('cb-policies-footnotes')
      expect(footnotes).not.toHaveTextContent(
        /Enabling Copilot in the CLI, Copilot in GitHub.com and Copilot Chat in GitHub Mobile will collect additional data and updated Product Terms apply. If preview features are enabled, you agree to pre-release terms/,
      )
      expect(footnotes).toHaveTextContent(/If preview features are enabled, you agree to pre-release terms/)
    })
  })
})

describe('a_chat settings cascade from business to organization', () => {
  it('when a_chat is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        a_chat: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_a_chat: true}),
    })

    expect(screen.getByText('Anthropic Claude 3.5 Sonnet in Copilot')).toBeInTheDocument()

    const aChatLockStatus = screen.getByTestId('cfb-policies-a-chat-feature-locked')
    expect(aChatLockStatus).toHaveTextContent('enabled')
  })

  it('when a_chat is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        a_chat: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_a_chat: true}),
    })

    expect(screen.getByText('Anthropic Claude 3.5 Sonnet in Copilot')).toBeInTheDocument()

    const aChatLockStatus = screen.getByTestId('cfb-policies-a-chat-feature-locked')
    expect(aChatLockStatus).toHaveTextContent('disabled')
  })

  it('when a_chat has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        a_chat: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_a_chat: true}),
    })

    expect(screen.getByText('Anthropic Claude 3.5 Sonnet in Copilot')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-a-chat-control')
    expect(actionMenu).toBeInTheDocument()
  })
})
describe('a_f settings cascade from business to organization', () => {
  it('when a_f is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        a_f: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_a_f: true}),
    })

    expect(screen.getByText('Anthropic Claude 3.7 Sonnet in Copilot')).toBeInTheDocument()

    const aFLockStatus = screen.getByTestId('cfb-policies-a-f-feature-locked')
    expect(aFLockStatus).toHaveTextContent('enabled')
  })

  it('when a_f is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        a_f: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_a_f: true}),
    })

    expect(screen.getByText('Anthropic Claude 3.7 Sonnet in Copilot')).toBeInTheDocument()

    const aFLockStatus = screen.getByTestId('cfb-policies-a-f-feature-locked')
    expect(aFLockStatus).toHaveTextContent('disabled')
  })

  it('when a_f has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        a_f: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_a_f: true}),
    })

    expect(screen.getByText('Anthropic Claude 3.7 Sonnet in Copilot')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-a-f-control')
    expect(actionMenu).toBeInTheDocument()
  })
})

describe('g_chat settings cascade from business to organization', () => {
  it('when g_chat is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        g_chat: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_g_chat: true}),
    })

    expect(screen.getByText('Google Gemini 2.0 Flash in Copilot')).toBeInTheDocument()

    const aChatLockStatus = screen.getByTestId('cfb-policies-g-chat-feature-locked')
    expect(aChatLockStatus).toHaveTextContent('enabled')
  })

  it('when g_chat is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        g_chat: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_g_chat: true}),
    })

    expect(screen.getByText('Google Gemini 2.0 Flash in Copilot')).toBeInTheDocument()

    const gChatLockStatus = screen.getByTestId('cfb-policies-g-chat-feature-locked')
    expect(gChatLockStatus).toHaveTextContent('disabled')
  })

  it('when g_chat has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        g_chat: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_g_chat: true}),
    })

    expect(screen.getByText('Google Gemini 2.0 Flash in Copilot')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-g-chat-control')
    expect(actionMenu).toBeInTheDocument()
  })
})

describe('o1 settings cascade from business to organization', () => {
  it('when o1 is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o1: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o1: true}),
    })

    expect(screen.getByText('OpenAI o1 models in Copilot')).toBeInTheDocument()

    const aChatLockStatus = screen.getByTestId('cfb-policies-o1-feature-locked')
    expect(aChatLockStatus).toHaveTextContent('enabled')
  })

  it('when o1 is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o1: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o1: true}),
    })

    expect(screen.getByText('OpenAI o1 models in Copilot')).toBeInTheDocument()

    const bingLockStatus = screen.getByTestId('cfb-policies-o1-feature-locked')
    expect(bingLockStatus).toHaveTextContent('disabled')
  })

  it('when o1 has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o1: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_o1: true}),
    })

    expect(screen.getByText('OpenAI o1 models in Copilot')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-o1-control')
    expect(actionMenu).toBeInTheDocument()
  })
})

describe('o3 settings cascade from business to organization', () => {
  it('when o3 is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o3: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o3: true}),
    })

    expect(screen.getByText('OpenAI o3 models in Copilot')).toBeInTheDocument()

    const aChatLockStatus = screen.getByTestId('cfb-policies-o3-feature-locked')
    expect(aChatLockStatus).toHaveTextContent('enabled')
  })

  it('when o3 is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o3: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o3: true}),
    })

    expect(screen.getByText('OpenAI o3 models in Copilot')).toBeInTheDocument()

    const bingLockStatus = screen.getByTestId('cfb-policies-o3-feature-locked')
    expect(bingLockStatus).toHaveTextContent('disabled')
  })

  it('when o3 has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o3: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_o3: true}),
    })

    expect(screen.getByText('OpenAI o3 models in Copilot')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-o3-control')
    expect(actionMenu).toBeInTheDocument()
  })
})
describe('o_ff settings cascade from business to organization', () => {
  it('when o_ff is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o_ff: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o_ff: true}),
    })

    expect(screen.getByText('OpenAI GPT-4.5 model in Copilot')).toBeInTheDocument()

    const aChatLockStatus = screen.getByTestId('cfb-policies-o-ff-feature-locked')
    expect(aChatLockStatus).toHaveTextContent('enabled')
  })

  it('when o_ff is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o_ff: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o_ff: true}),
    })

    expect(screen.getByText('OpenAI GPT-4.5 model in Copilot')).toBeInTheDocument()

    const oFFStatus = screen.getByTestId('cfb-policies-o-ff-feature-locked')
    expect(oFFStatus).toHaveTextContent('disabled')
  })

  it('when o_ff has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o_ff: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_o_ff: true}),
    })

    expect(screen.getByText('OpenAI GPT-4.5 model in Copilot')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-o-ff-control')
    expect(actionMenu).toBeInTheDocument()
  })
})

describe('o_f settings cascade from business to organization', () => {
  it('when o_f is configured for the business as enabled it cannot be configured for the org and displays as enabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o_f: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: true,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: false,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o_f: true}),
    })

    expect(screen.getByText('TEMP O_F')).toBeInTheDocument()

    const oFLockStatus = screen.getByTestId('cfb-policies-o-f-feature-locked')
    expect(oFLockStatus).toHaveTextContent('enabled')
  })

  it('when o_f is configured for the business as disabled it cannot be configured for the org and displays as disabled', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o_f: {
          configurable: false,
          visible: true,
          options: [
            {
              id: 'enabled_option',
              title: 'enabled',
              description: 'enabled',
              value: 'enabled',
              selected: false,
            },
            {
              id: 'disabled_option',
              title: 'disabled',
              description: 'disabled',
              value: 'disabled',
              selected: true,
            },
          ],
        },
      }),
      appPayload: makeFeatureFlags({copilot_o_f: true}),
    })

    expect(screen.getByText('TEMP O_F')).toBeInTheDocument()

    const oFLockStatus = screen.getByTestId('cfb-policies-o-f-feature-locked')
    expect(oFLockStatus).toHaveTextContent('disabled')
  })

  it('when o_f has no policy for the business it can be configured for the org', () => {
    render(<Models />, {
      routePayload: makePoliciesRoutePayload({
        o_f: {
          configurable: true,
          visible: true,
        },
      }),
      appPayload: makeFeatureFlags({copilot_o_f: true}),
    })

    expect(screen.getByText('TEMP O_F')).toBeInTheDocument()

    const actionMenu = screen.getByTestId('cfb-policies-o-f-control')
    expect(actionMenu).toBeInTheDocument()
  })
})

// --

function makeFeatureFlags(flags: Record<string, boolean> = {}) {
  return {
    enabled_features: {
      ...flags,
    },
  }
}
