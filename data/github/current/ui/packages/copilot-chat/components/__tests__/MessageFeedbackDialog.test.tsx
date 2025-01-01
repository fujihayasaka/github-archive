import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import React, {act} from 'react'

import {getCopilotChatProviderProps} from '../../test-utils/mock-data'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {CopilotChatProvider} from '../../utils/CopilotChatContext'
import {type FeedbackDialogRef, MessageFeedbackDialog} from '../MessageFeedbackDialog'

const sendFeedback = jest.fn()
jest.mock('../../utils/copilot-chat-service', () => ({
  ...jest.requireActual('../../utils/copilot-chat-service'),
  CopilotChatService: jest.fn().mockImplementation(() => ({sendFeedback})),
}))

beforeEach(() => {
  sendFeedback.mockResolvedValue({ok: true})
  jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(false)
})

afterEach(() => {
  jest.clearAllMocks()
})

it('renders closed', () => {
  const props = getCopilotChatProviderProps()
  const dialogRef = React.createRef<FeedbackDialogRef>()
  render(
    <CopilotChatProvider {...props}>
      <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
    </CopilotChatProvider>,
  )

  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})

describe('openDialog', () => {
  it('opens feedback dialog', async () => {
    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Look for things identifying the feedback dialog
    expect(await within(dialog).findByRole('textbox')).toBeInTheDocument()
    expect(await within(dialog).findAllByRole('radio')).toHaveLength(2)
    expect(await within(dialog).findByRole('button', {name: /send/i})).toBeInTheDocument()
  })

  it('opens survey dialog when survey flag is on', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(true)

    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Look for things identifying the survey dialog
    expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()
  })

  it('carries initial option through survey dialog to feedback dialog', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(true)

    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog('NEGATIVE'))

    let dialog = await screen.findByRole('dialog')
    await user.click(within(dialog).getByRole('button', {name: /no, thanks/i}))

    dialog = await screen.findByRole('dialog')
    expect(await within(dialog).findByRole('radio', {name: 'Bad'})).toBeChecked()
    expect(await within(dialog).findByRole('radio', {name: 'Good'})).not.toBeChecked()
  })
})

describe('user submits feedback', () => {
  it('sends user provided feedback to the server with message context', async () => {
    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog('NEGATIVE'))

    const dialog = await screen.findByRole('dialog')
    const textbox = await within(dialog).findByRole('textbox')
    await user.click(textbox)
    await user.paste('This is my feedback.')

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(sendFeedback).toHaveBeenCalledWith(
      expect.objectContaining({
        feedback: 'NEGATIVE',
        feedbackChoice: [],
        messageId: 'my-message',
        threadId: 'my-thread',
        textResponse: 'This is my feedback.',
      }),
    )
  })

  it('shows an error when the user does not select a rating', async () => {
    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')

    const expectedText = 'Please select a rating.'
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
    expect(sendFeedback).not.toHaveBeenCalled()
  })

  it('shows an error when the user provides feedback text longer than limit', async () => {
    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog('POSITIVE'))

    const dialog = await screen.findByRole('dialog')

    const limit = 500
    const expectedText = `Please keep your feedback within ${limit} characters or less.`
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const textbox = await within(dialog).findByRole('textbox')
    await user.click(textbox)
    await user.paste('a'.repeat(limit + 1))

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
    expect(sendFeedback).not.toHaveBeenCalled()
  })

  it('shows an error when sending the feedback to the server returns a not okay response', async () => {
    sendFeedback.mockResolvedValue({ok: false})
    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog('POSITIVE'))

    const dialog = await screen.findByRole('dialog')

    const expectedText = `An error occurred while submitting your feedback.`
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
    expect(sendFeedback).toHaveBeenCalled()
  })

  it('shows an error when sending the feedback to the server returns a rejected promise response', async () => {
    sendFeedback.mockRejectedValue(new Error('test error'))
    const props = getCopilotChatProviderProps()
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(
      <CopilotChatProvider {...props}>
        <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
      </CopilotChatProvider>,
    )

    act(() => dialogRef.current?.openDialog('POSITIVE'))

    const dialog = await screen.findByRole('dialog')

    const expectedText = `An error occurred while submitting your feedback.`
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
    expect(sendFeedback).toHaveBeenCalled()
  })

  describe('onClose', () => {
    it('gets called when the feedback is successfully submitted', async () => {
      const onClose = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" onClose={onClose} />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog('POSITIVE'))

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onClose).toHaveBeenCalled()
      expect(dialog).not.toBeInTheDocument()
    })

    it('does not get called when the feedback is not successfully submitted', async () => {
      const onClose = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" onClose={onClose} />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onClose).not.toHaveBeenCalled()
      expect(dialog).toBeInTheDocument()
    })
  })

  describe('onSubmitted', () => {
    it('gets called when the feedback is successfully submitted', async () => {
      const onSubmitted = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog
            ref={dialogRef}
            messageId="my-message"
            threadId="my-thread"
            onSubmitted={onSubmitted}
          />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog('POSITIVE'))

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmitted).toHaveBeenCalledWith('POSITIVE')
    })

    it('does not get called when the feedback is not successfully submitted', async () => {
      const onSubmitted = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog
            ref={dialogRef}
            messageId="my-message"
            threadId="my-thread"
            onSubmitted={onSubmitted}
          />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmitted).not.toHaveBeenCalled()
    })
  })
})

describe('user dismisses feedback dialog', () => {
  describe('by "Cancel" button', () => {
    it('closes dialog and calls onClose', async () => {
      const onClose = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" onClose={onClose} />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      await user.click(within(dialog).getByRole('button', {name: /cancel/i}))

      expect(onClose).toHaveBeenCalled()
      expect(dialog).not.toBeInTheDocument()
    })
  })

  describe('by "Close" button', () => {
    it('closes dialog and calls onClose', async () => {
      const onClose = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" onClose={onClose} />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      await user.click(within(dialog).getByRole('button', {name: /close/i}))

      expect(onClose).toHaveBeenCalled()
      expect(dialog).not.toBeInTheDocument()
    })
  })
})

describe('user dismisses survey dialog', () => {
  beforeEach(() => {
    jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(true)
  })

  describe('by "No thanks" button', () => {
    it('opens feedback dialog', async () => {
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      let dialog = await screen.findByRole('dialog')

      // Look for things identifying the survey dialog
      expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()

      await user.click(within(dialog).getByRole('button', {name: /no, thanks/i}))

      // Look for things identifying the feedback dialog
      dialog = await screen.findByRole('dialog')
      expect(await within(dialog).findByRole('textbox')).toBeInTheDocument()
      expect(await within(dialog).findAllByRole('radio')).toHaveLength(2)
      expect(await within(dialog).findByRole('button', {name: /send/i})).toBeInTheDocument()
    })

    it('does not call onClose', async () => {
      const onClose = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" onClose={onClose} />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      await user.click(within(dialog).getByRole('button', {name: /no, thanks/i}))

      expect(onClose).not.toHaveBeenCalled()
    })
  })

  describe('by "Close" button', () => {
    it('closes dialog and calls onClose', async () => {
      const onClose = jest.fn()
      const props = getCopilotChatProviderProps()
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(
        <CopilotChatProvider {...props}>
          <MessageFeedbackDialog ref={dialogRef} messageId="my-message" threadId="my-thread" onClose={onClose} />
        </CopilotChatProvider>,
      )

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')

      // Look for things identifying the survey dialog
      expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()

      await user.click(within(dialog).getByRole('button', {name: /close/i}))

      expect(onClose).toHaveBeenCalled()
      expect(dialog).not.toBeInTheDocument()
    })
  })
})
