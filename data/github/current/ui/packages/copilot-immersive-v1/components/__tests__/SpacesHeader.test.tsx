import {mockClientEnv} from '@github-ui/client-env/mock'
import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {MockContentPreviewContextProvider} from '../../test-utils/MockContentPreviewContextProvider'
import {SpacesHeader} from '../Spaces/SpacesHeader'

const userEvent = setupUserEvent()

jest.mock('@github-ui/ssr-utils', () => ({
  ...jest.requireActual('@github-ui/ssr-utils'),
  get ssrSafeLocation() {
    return {
      pathname: '/copilot/spaces/monalisa/123',
      search: '',
      key: 'key',
      hash: '',
      state: null,
    }
  },
}))

describe('SpacesHeader', () => {
  let copilot: CustomCopilot

  beforeEach(() => {
    copilot = getCustomCopilotMock({
      id: 123,
      oldId: 123,
      owner: 'monalisa',
    })
  })

  function renderSpacesHeader() {
    const customCopilots = [copilot]

    render(
      <MockContentPreviewContextProvider>
        <CopilotChatProvider
          {...getCopilotChatProviderProps()}
          testReducerState={{
            ...getDefaultReducerState('3', undefined, 'immersive'),
            messagesLoading: {state: 'loaded' as const, error: null},
            selectedThreadID: null,
            customCopilots,
          }}
        >
          <SpacesHeader isSidebarOpen={false} />
        </CopilotChatProvider>
      </MockContentPreviewContextProvider>,
    )
  }

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('render visibility dialog if space is org owned and ff is enabled', async () => {
    copilot.ownerIsOrg = true
    mockClientEnv({
      featureFlags: ['copilot_custom_copilots_visibility'],
    })

    renderSpacesHeader()
    await userEvent.click(screen.getByLabelText('Menu'))
    await userEvent.click(await screen.findByText('Share'))
    expect(await screen.findByTestId('custom-copilot-visibility')).toBeVisible()
  })

  it('hide edit and delete buttons if read only', async () => {
    copilot.editable = false
    mockClientEnv({
      featureFlags: ['copilot_custom_copilots_org_owned'],
    })

    renderSpacesHeader()
    expect(screen.queryByText('Edit')).not.toBeInTheDocument()
    await userEvent.click(screen.getByLabelText('Menu'))
    expect(screen.queryByText('Delete')).not.toBeInTheDocument()
  })

  it('show edit and delete buttons if editable', async () => {
    copilot.editable = true
    mockClientEnv({
      featureFlags: ['copilot_custom_copilots_org_owned'],
    })

    renderSpacesHeader()
    expect(screen.queryByText('Edit')).toBeVisible()
    await userEvent.click(screen.getByLabelText('Menu'))
    expect(screen.queryByText('Delete')).toBeVisible()
  })
})
