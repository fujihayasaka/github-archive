import {mockClientEnv} from '@github-ui/client-env/mock'
import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import type {CustomCopilot} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {CopilotSpacesMenu} from '../Spaces/SpaceMenu'

const userEvent = setupUserEvent()

describe('CopilotSpacesMenu', () => {
  const onDelete = jest.fn()

  const copilot: CustomCopilot = getCustomCopilotMock()

  function renderSpaceMenu() {
    const customCopilots = [copilot]

    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} customCopilots={customCopilots}>
        <CopilotSpacesMenu onDelete={onDelete} copilot={copilot} />
      </CopilotChatProvider>,
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

    renderSpaceMenu()
    await userEvent.click(screen.getByLabelText('Manage space'))
    await userEvent.click(await screen.findByText('Share'))
    expect(await screen.findByTestId('custom-copilot-visibility')).toBeVisible()
  })

  it('render edit and delete buttons if ff is disabled', async () => {
    copilot.editable = false

    renderSpaceMenu()
    await userEvent.click(screen.getByLabelText('Manage space'))
    expect(screen.getByText('Edit')).toBeVisible()
    expect(screen.getByText('Delete')).toBeVisible()
  })

  it('render edit and delete buttons if editable', async () => {
    copilot.editable = true
    mockClientEnv({
      featureFlags: ['copilot_custom_copilots_org_owned'],
    })

    renderSpaceMenu()
    await userEvent.click(screen.getByLabelText('Manage space'))
    expect(screen.getByText('Edit')).toBeVisible()
    expect(screen.getByText('Delete')).toBeVisible()
  })

  it('hide edit and delete buttons if read only', async () => {
    copilot.editable = false
    mockClientEnv({
      featureFlags: ['copilot_custom_copilots_org_owned'],
    })

    renderSpaceMenu()
    await userEvent.click(screen.getByLabelText('Manage space'))
    expect(screen.queryByText('Edit')).not.toBeInTheDocument()
    expect(screen.queryByText('Delete')).not.toBeInTheDocument()
  })
})
