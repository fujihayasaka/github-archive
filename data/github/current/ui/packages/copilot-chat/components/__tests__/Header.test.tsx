import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import React from 'react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {DialogType} from '../../utils/copilot-chat-types'
import {CopilotChatProvider, type CopilotChatProviderProps} from '../../utils/CopilotChatContext'
import {Header} from '../Header'
import {MenuPortalContainer} from '../PortalContainerUtils'

const userEvent = setupUserEvent()

describe('PersonalInstructionsDialog', () => {
  let chatProviderProps: CopilotChatProviderProps

  beforeEach(() => {
    chatProviderProps = getCopilotChatProviderProps()
    chatProviderProps.chatIsOpen = true
    jest.clearAllMocks()
  })

  test('rener personal instructions', async () => {
    renderHeader()

    await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
    expect(await screen.findByText('Personal instructions')).toBeInTheDocument()
  })

  function renderHeader(props = {}) {
    render(
      <CopilotChatProvider {...chatProviderProps}>
        <MenuPortalContainer />
        <Header
          staffDialogRef={React.createRef()}
          showStaffDialog={DialogType.None}
          setShowStaffDialog={() => {}}
          {...props}
        />
      </CopilotChatProvider>,
    )
  }
})
