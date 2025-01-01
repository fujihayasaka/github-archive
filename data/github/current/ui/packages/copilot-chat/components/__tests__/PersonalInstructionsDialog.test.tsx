import {mockFetch} from '@github-ui/mock-fetch'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import React, {type RefObject} from 'react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {suggestedPersonalInstructions} from '../../utils/custom-instructions'
import {PersonalInstructionsDialog} from '../PersonalInstructionsDialog'

const userEvent = setupUserEvent()

describe('PersonalInstructionsDialog', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders a Dialog with a form for updating personal instructions', async () => {
    const prompt = 'My new instructions'
    const onDismissMock = jest.fn()
    mockFetch.mockRouteOnce('/copilot/personal_instructions', {}, {ok: true})
    const anchorRef = React.createRef<HTMLButtonElement>()

    renderPersonalInstructionsDialog({onDismiss: onDismissMock, anchorRef})

    await userEvent.type(screen.getByTestId('prompt-input'), prompt)
    expect(await screen.findByTestId('current-character-count')).toHaveTextContent(`${prompt.length}`)
    await userEvent.click(screen.getByText('Save'))

    expect(mockFetch.fetch).toHaveBeenCalledWith(
      '/copilot/personal_instructions',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({prompt}),
      }),
    )
    expect(onDismissMock).toHaveBeenCalled()
  })

  test('renders error when server responds with an error', async () => {
    const anchorRef = React.createRef<HTMLButtonElement>()
    const errorMessage = 'Failed to save the instructions'
    const onDismissMock = jest.fn()
    mockFetch.mockRouteOnce(
      '/copilot/personal_instructions',
      {},
      {
        ok: false,
        json: () => {
          return Promise.resolve({errorMessage})
        },
      },
    )

    renderPersonalInstructionsDialog({onDismiss: onDismissMock, anchorRef})

    await userEvent.type(screen.getByTestId('prompt-input'), 'My new instructions')
    await userEvent.click(screen.getByText('Save'))

    expect(mockFetch.fetch).toHaveBeenCalledWith(
      '/copilot/personal_instructions',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({prompt: 'My new instructions'}),
      }),
    )
    expect(onDismissMock).not.toHaveBeenCalled()
    expect(await screen.findByTestId('error-message')).toHaveTextContent(errorMessage)
  })

  test('renders a Dialog with a form for updating personal instructions with templates', async () => {
    const anchorRef = React.createRef<HTMLButtonElement>()
    const onDismissMock = jest.fn()
    mockFetch.mockRouteOnce('/copilot/personal_instructions', {}, {ok: true})

    renderPersonalInstructionsDialog({onDismiss: onDismissMock, anchorRef})

    await userEvent.click(screen.getByTestId('toggle-templates'))

    for (const key of Object.keys(suggestedPersonalInstructions)) {
      await userEvent.click(screen.getByText(key))

      expect(await screen.findByTestId('prompt-input')).toHaveTextContent(
        suggestedPersonalInstructions[key]?.body?.replaceAll('\n', ' ').trim() ?? '',
      )
    }
  })

  function renderPersonalInstructionsDialog(props: {onDismiss: () => void; anchorRef: RefObject<HTMLButtonElement>}) {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()}>
        <button ref={props.anchorRef} />
        <PersonalInstructionsDialog onDismiss={props.onDismiss} returnFocusRef={props.anchorRef} />
      </CopilotChatProvider>,
    )
  }
})
