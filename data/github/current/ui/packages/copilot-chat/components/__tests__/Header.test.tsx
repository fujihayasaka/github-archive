import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import React from 'react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {type CopilotChatRepo, type CopilotCustomInstructions, DialogType} from '../../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {copilotLocalStorage} from '../../utils/copilot-local-storage'
import {CopilotChatProvider, type CopilotChatProviderProps} from '../../utils/CopilotChatContext'
import {Header} from '../Header'
import {MenuPortalContainer} from '../PortalContainerUtils'

const userEvent = setupUserEvent()

const mockRepoCustomInstructions: CopilotCustomInstructions = {type: 'Repository', owner: 'github', prompt: 'beep boop'}

describe('Header', () => {
  let chatProviderProps: CopilotChatProviderProps

  beforeEach(() => {
    chatProviderProps = getCopilotChatProviderProps()
    chatProviderProps.chatIsOpen = true
    ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = [mockRepoCustomInstructions]
    jest.spyOn(copilotFeatureFlags, 'repoCustomInstructions', 'get').mockReturnValue(true)
    copilotLocalStorage.setRepoCustomInstructionsState(true)
    jest.clearAllMocks()
  })

  describe('Custom Instructions', () => {
    test('render disable link if custom instructions is feature enabled', async () => {
      ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = [mockRepoCustomInstructions]
      renderHeader()

      await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
      expect(await screen.findByText('Disable custom instructions')).toBeInTheDocument()
    })

    test('render enable link if custom instructions is feature enabled', async () => {
      ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = [mockRepoCustomInstructions]
      copilotLocalStorage.setRepoCustomInstructionsState(false)
      renderHeader()

      await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
      expect(await screen.findByText('Enable custom instructions')).toBeInTheDocument()
    })

    test('render disable link if custom instructions is preview feature enabled', async () => {
      jest.spyOn(copilotFeatureFlags, 'repoCustomInstructionsPreview', 'get').mockReturnValue(true)
      copilotLocalStorage.setRepoCustomInstructionsState(true)
      renderHeader()

      await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
      expect(await screen.findByText('Disable custom instructions')).toBeInTheDocument()
    })

    test('do not render link if custom instructions is empty', async () => {
      ;(chatProviderProps.topic as CopilotChatRepo).customInstructions = []
      jest.spyOn(copilotFeatureFlags, 'repoCustomInstructionsPreview', 'get').mockReturnValue(true)
      copilotLocalStorage.setRepoCustomInstructionsState(true)
      renderHeader()

      await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
      expect(screen.queryByText('Disable custom instructions')).not.toBeInTheDocument()
    })

    test('render link if topics as reference is enabled', async () => {
      jest.spyOn(copilotFeatureFlags, 'repoCustomInstructionsPreview', 'get').mockReturnValue(true)
      jest.spyOn(copilotFeatureFlags, 'topicsAsReferences', 'get').mockReturnValue(true)

      copilotLocalStorage.setRepoCustomInstructionsState(true)
      renderHeader()

      await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
      expect(screen.getByText('Disable custom instructions')).toBeInTheDocument()
    })
  })

  describe('PersonalInstructionsDialog', () => {
    test('render personal instructions', async () => {
      renderHeader()

      await userEvent.click(screen.getByRole('button', {name: 'Conversation options'}))
      expect(await screen.findByText('Personal instructions')).toBeInTheDocument()
    })
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
