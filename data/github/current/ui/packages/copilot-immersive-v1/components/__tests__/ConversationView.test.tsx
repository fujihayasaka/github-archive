import {ChatStateProvider, CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import {
  type CopilotChatEntitlementQuotas,
  type CopilotChatModel,
  CopilotLicenseType,
  type CustomCopilot,
} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {mockFetch} from '@github-ui/mock-fetch'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen, waitFor} from '@testing-library/react'
import React from 'react'

import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {ConversationView} from '../ConversationView'

jest.mock('@github-ui/feature-flags')

describe('Can use Copilot chat with premium request quota tracking enabled', () => {
  beforeEach(() => {
    jest.spyOn(copilotFeatureFlags, 'premiumRequestQuotasEnabled', 'get').mockReturnValue(true)
  })

  const threads = new Map([
    [
      'empty-thread',
      {
        id: 'empty-thread',
        name: 'conversation empty-thread',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
  ])

  it('fully licensed user can use chat with no quotas returned', () => {
    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.getByText(/You have reached your/)).toBeInTheDocument()
  })

  it('limited licensed user can use chat with quotas returned', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_limited',
      quotas: {
        remaining: {
          chat: 100,
          chatPercentage: 100,
        },
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByText(/You have reached your/)).not.toBeInTheDocument()
  })

  it('limited licensed user can not use chat with no remaining quota returned', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: CopilotLicenseType.LicensedLimited,
      quotas: {
        remaining: {
          chat: 0,
          chatPercentage: 0,
        },
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()

    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.queryByTestId('copilot-chat-input-textarea')).not.toBeInTheDocument()
    expect(screen.getByText(/You have reached your free plan limit/)).toBeInTheDocument()
  })

  it('fully licensed user can use use premium model with premium interactions available', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_full',
      quotas: {
        remaining: {
          premiumInteractions: 100,
          premiumInteractionsPercentage: 100,
        },
        resetDate: new Date().toISOString(),
        overagesEnabled: false,
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
                model: {
                  billing: {
                    // eslint-disable-next-line camelcase
                    is_premium: true,
                  },
                } as CopilotChatModel,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByText(/You have reached your/)).not.toBeInTheDocument()
  })

  it('fully licensed user can not use use premium model with premium interactions exhausted', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_full',
      quotas: {
        remaining: {
          premiumInteractions: 0,
          premiumInteractionsPercentage: 0,
        },
        resetDate: new Date().toISOString(),
        overagesEnabled: false,
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
                model: {
                  billing: {
                    // eslint-disable-next-line camelcase
                    is_premium: true,
                  },
                } as CopilotChatModel,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.getByText(/You have reached your monthly limit for premium requests/)).toBeInTheDocument()
  })

  it('fully licensed user can use use premium model with premium interactions exhausted and overages enabled', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.threadId = null
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_full',
      quotas: {
        remaining: {
          premiumInteractions: 0,
          premiumInteractionsPercentage: 0,
        },
        resetDate: new Date().toISOString(),
        overagesEnabled: false,
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState(null, undefined, 'immersive'),
                threads,
                model: {
                  billing: {
                    // eslint-disable-next-line camelcase
                    is_premium: true,
                  },
                } as CopilotChatModel,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.getByText(/You have reached your/)).toBeInTheDocument()
  })
})

describe('Can use Copilot chat with premium request quota tracking disabled', () => {
  beforeEach(() => {
    jest.spyOn(copilotFeatureFlags, 'premiumRequestQuotasEnabled', 'get').mockReturnValue(false)
  })

  const threads = new Map([
    [
      'empty-thread',
      {
        id: 'empty-thread',
        name: 'conversation empty-thread',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      },
    ],
  ])

  it('fully licensed user can use chat with no quotas returned', () => {
    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...getCopilotChatProviderProps()}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByText(/You have reached your/)).not.toBeInTheDocument()
  })

  it('limited licensed user can use chat with quotas returned', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_limited',
      quotas: {
        remaining: {
          chat: 100,
        },
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByText(/You have reached your/)).not.toBeInTheDocument()
  })

  it('limited licensed user can not use chat with no remaining quota returned', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_limited',
      quotas: {
        remaining: {
          chat: 0,
        },
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()

    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.queryByTestId('copilot-chat-input-textarea')).not.toBeInTheDocument()
    expect(screen.getByText(/You have reached your free plan limit/)).toBeInTheDocument()
  })

  it('fully licensed user can use use premium model with premium interactions available', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_full',
      quotas: {
        remaining: {
          premiumInteractions: 100,
          premiumInteractionsPercentage: 100,
        },
        resetDate: new Date().toISOString(),
        overagesEnabled: false,
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
                model: {
                  billing: {
                    // eslint-disable-next-line camelcase
                    is_premium: true,
                  },
                } as CopilotChatModel,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByText(/You have reached your/)).not.toBeInTheDocument()
  })

  it('fully licensed user can use use premium model with premium interactions exhausted', () => {
    const providerProps = getCopilotChatProviderProps()
    providerProps.copilotChatPayload = {
      ...providerProps.copilotChatPayload,
      licenseType: 'licensed_full',
      quotas: {
        remaining: {
          premiumInteractions: 0,
          premiumInteractionsPercentage: 0,
        },
        resetDate: new Date().toISOString(),
        overagesEnabled: false,
      } as CopilotChatEntitlementQuotas,
    }

    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    renderRelay(
      () => (
        <CopilotChatProvider {...providerProps}>
          <ContentPreviewProvider>
            <ChatStateProvider
              state={{
                ...getDefaultReducerState('empty-thread', undefined, 'immersive'),
                threads,
                model: {
                  billing: {
                    // eslint-disable-next-line camelcase
                    is_premium: true,
                  },
                } as CopilotChatModel,
              }}
            >
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ChatStateProvider>
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    expect(screen.getByTestId('copilot-chat-input-textarea')).toBeInTheDocument()
    expect(screen.queryByText(/You have reached your/)).not.toBeInTheDocument()
  })
})

describe('Spaces', () => {
  const noOwnerSpace = getCustomCopilotMock({id: 123})
  const ownerSpace = getCustomCopilotMock({id: 789, owner: 'monalisa', name: 'Custom test space'})
  const tooBigSpace = getCustomCopilotMock({id: 999, owner: 'monalisa', sizePercentage: 101})
  const customCopilots: CustomCopilot[] = [ownerSpace, noOwnerSpace, tooBigSpace]

  const threads = new Map([
    [
      'space-thread',
      {
        id: 'space-thread',
        name: 'conversation space-thread',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        customCopilotID: 123,
      },
    ],
    [
      'ecaps-thread',
      {
        id: 'ecaps-thread',
        name: 'conversation ecaps-thread',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        customCopilotID: 789,
        customCopilotOwner: 'monalisa',
      },
    ],
    [
      'universe',
      {
        id: 'universe',
        name: 'conversation universe',
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        customCopilotID: 999,
        customCopilotOwner: 'monalisa',
      },
    ],
  ])

  describe('Owner field is not present for Space', () => {
    it('renders conversation view for a selected space', async () => {
      const textAreaRef = React.createRef<HTMLTextAreaElement>()
      mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots/123', noOwnerSpace)
      renderRelay(
        () => (
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ContentPreviewProvider>
              <ChatStateProvider
                state={{
                  ...getDefaultReducerState('space-thread', undefined, 'immersive'),
                  threads,
                  customCopilots,
                }}
              >
                <ConversationView isMobile={false} textAreaRef={textAreaRef} />
              </ChatStateProvider>
            </ContentPreviewProvider>
          </CopilotChatProvider>
        ),
        {
          relay: {
            queries: {},
          },
          wrapper: Wrapper,
        },
      )

      await waitFor(() => expect(mockFetch.fetch).toHaveBeenCalled())
      expect(
        screen.queryByText(
          'Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization.',
        ),
      ).not.toBeInTheDocument()
    })

    it('does not render a banner while the space data is loading', () => {
      const textAreaRef = React.createRef<HTMLTextAreaElement>()
      // by not providing a mock result for useFetchCustomCopilot, we simulate a loading state
      renderRelay(
        () => (
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ContentPreviewProvider>
              <ChatStateProvider
                state={{
                  ...getDefaultReducerState('space-thread', undefined, 'immersive'),
                  threads,
                  customCopilots,
                }}
              >
                <ConversationView isMobile={false} textAreaRef={textAreaRef} />
              </ChatStateProvider>
            </ContentPreviewProvider>
          </CopilotChatProvider>
        ),
        {
          relay: {
            queries: {},
          },
          wrapper: Wrapper,
        },
      )

      expect(
        screen.queryByText(
          'Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization.',
        ),
      ).not.toBeInTheDocument()
    })

    it('renders a banner that disables chat if the space cannot be found', async () => {
      const textAreaRef = React.createRef<HTMLTextAreaElement>()
      mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots/789', null, {status: 404, ok: false})
      const testReducerState = {
        ...getDefaultReducerState('space-deleted', undefined, 'immersive'),
        threads: new Map([
          [
            'space-deleted',
            {
              id: 'space-deleted',
              name: 'conversation space-deleted',
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString(),
              customCopilotID: 789,
            },
          ],
        ]),
      }

      renderRelay(
        () => (
          <CopilotChatProvider testReducerState={testReducerState} {...getCopilotChatProviderProps()}>
            <ContentPreviewProvider>
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ContentPreviewProvider>
          </CopilotChatProvider>
        ),
        {
          relay: {
            queries: {},
          },
          wrapper: Wrapper,
        },
      )
      await waitFor(() => expect(mockFetch.fetch).toHaveBeenCalled())
      expect(
        await screen.findByText(
          'Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization.',
        ),
      ).toBeInTheDocument()
    })
  })

  describe('Owner is present for Space', () => {
    it('renders conversation view for a selected space with no banner when the space is available', async () => {
      mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots/monalisa/789', ownerSpace)
      const textAreaRef = React.createRef<HTMLTextAreaElement>()
      renderRelay(
        () => (
          <CopilotChatProvider {...getCopilotChatProviderProps()}>
            <ContentPreviewProvider>
              <ChatStateProvider
                state={{
                  ...getDefaultReducerState('ecaps-thread', undefined, 'immersive'),
                  threads,
                  customCopilots,
                }}
              >
                <ConversationView isMobile={false} textAreaRef={textAreaRef} />
              </ChatStateProvider>
            </ContentPreviewProvider>
          </CopilotChatProvider>
        ),
        {
          relay: {
            queries: {},
          },
          wrapper: Wrapper,
        },
      )

      // Note the breadcrumb is rendered by the SpacesHeader, which depends on the chat state.customCopilots
      await waitFor(() => expect(mockFetch.fetch).toHaveBeenCalled())
      expect(
        screen.queryByText(
          'Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization.',
        ),
      ).not.toBeInTheDocument()
    })

    it('renders a banner that disables chat if the space cannot be found', async () => {
      const textAreaRef = React.createRef<HTMLTextAreaElement>()
      mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots/monalisa/123', null, {status: 404, ok: false})
      const testReducerState = {
        ...getDefaultReducerState('space-deleted', undefined, 'immersive'),
        threads: new Map([
          [
            'space-deleted',
            {
              id: 'space-deleted',
              name: 'conversation space-deleted',
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString(),
              customCopilotOwner: 'monalisa',
              customCopilotID: 123,
            },
          ],
        ]),
      }

      renderRelay(
        () => (
          <CopilotChatProvider testReducerState={testReducerState} {...getCopilotChatProviderProps()}>
            <ContentPreviewProvider>
              <ConversationView isMobile={false} textAreaRef={textAreaRef} />
            </ContentPreviewProvider>
          </CopilotChatProvider>
        ),
        {
          relay: {
            queries: {},
          },
          wrapper: Wrapper,
        },
      )

      await waitFor(() => expect(mockFetch.fetch).toHaveBeenCalled())
      expect(
        await screen.findByText(
          'Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization.',
        ),
      ).toBeInTheDocument()
    })
  })

  it('renders a banner that disables chat if the space exceeds the maximum content limit', async () => {
    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots/monalisa/999', tooBigSpace)
    const testReducerState = {
      ...getDefaultReducerState('universe', undefined, 'immersive'),
      threads,
      customCopilots,
    }

    renderRelay(
      () => (
        <CopilotChatProvider testReducerState={testReducerState} {...getCopilotChatProviderProps()}>
          <ContentPreviewProvider>
            <ConversationView isMobile={false} textAreaRef={textAreaRef} />
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await waitFor(() => expect(mockFetch.fetch).toHaveBeenCalled())
    expect(
      await screen.findByText(
        "You've exceeded the size limit for this space. Remove some references to continue chatting.",
      ),
    ).toBeInTheDocument()
  })

  it('renders the correct banner that disables chat if the space is deleted AND exceeds the maximum content limit', async () => {
    const textAreaRef = React.createRef<HTMLTextAreaElement>()
    mockFetch.mockRouteOnce('/github-copilot/chat/custom_copilots/monalisa/999', null, {status: 404, ok: false})
    const testReducerState = {
      ...getDefaultReducerState('universe', undefined, 'immersive'),
      threads,
    }

    renderRelay(
      () => (
        <CopilotChatProvider testReducerState={testReducerState} {...getCopilotChatProviderProps()}>
          <ContentPreviewProvider>
            <ConversationView isMobile={false} textAreaRef={textAreaRef} />
          </ContentPreviewProvider>
        </CopilotChatProvider>
      ),
      {
        relay: {
          queries: {},
        },
        wrapper: Wrapper,
      },
    )

    await waitFor(() => expect(mockFetch.fetch).toHaveBeenCalled())
    expect(
      await screen.findByText(
        'Conversation unavailable. The linked space may have been deleted, or you might be signed out of your organization.',
      ),
    ).toBeInTheDocument()
  })
})
