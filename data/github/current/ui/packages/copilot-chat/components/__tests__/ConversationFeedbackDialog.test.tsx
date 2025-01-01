import {mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import React, {act} from 'react'

import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'
import {ConversationFeedbackDialog, type FeedbackDialogRef} from '../ConversationFeedbackDialog'

beforeEach(() => {
  jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(false)
})

afterEach(() => {
  jest.clearAllMocks()
})

it('renders closed', () => {
  const dialogRef = React.createRef<FeedbackDialogRef>()
  render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})

describe('openDialog', () => {
  it('opens feedback dialog', async () => {
    const dialogRef = React.createRef<FeedbackDialogRef>()
    render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Look for things identifying the feedback dialog
    expect(await within(dialog).findByRole('textbox')).toBeInTheDocument()
    expect(await within(dialog).findAllByRole('radio')).toHaveLength(4)
    expect(await within(dialog).findByRole('button', {name: /send/i})).toBeInTheDocument()
  })

  it('opens survey dialog when survey flag is on', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(true)

    const dialogRef = React.createRef<FeedbackDialogRef>()
    render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    // Look for things identifying the survey dialog
    expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()
  })

  it('carries initial option through survey dialog to feedback dialog', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(true)

    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog(2))

    let dialog = await screen.findByRole('dialog')
    await user.click(within(dialog).getByRole('button', {name: /no, thanks/i}))

    dialog = await screen.findByRole('dialog')
    expect(await within(dialog).findByRole('radio', {name: 'Hate it'})).not.toBeChecked()
    expect(await within(dialog).findByRole('radio', {name: 'Not great'})).toBeChecked()
    expect(await within(dialog).findByRole('radio', {name: 'It’s ok'})).not.toBeChecked()
    expect(await within(dialog).findByRole('radio', {name: 'Love it'})).not.toBeChecked()
  })
})

describe('user submits feedback', () => {
  it('sends user provided feedback to the server with mode context', async () => {
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="immersive" />)

    act(() => dialogRef.current?.openDialog(2))

    const dialog = await screen.findByRole('dialog')
    const textbox = await within(dialog).findByRole('textbox')
    await user.click(textbox)
    await user.paste('This is my feedback.')

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(mockFetch.fetch).toHaveBeenCalled()
    for (const expected of ['"rating":2', '"content":"This is my feedback."', '"mode":"immersive"']) {
      expect(mockFetch.fetch).toHaveBeenCalledWith(
        '/github-copilot/feedback',
        expect.objectContaining({
          body: expect.stringContaining(expected),
        }),
      )
    }
  })

  it('shows an error when the user does not select a rating', async () => {
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')

    const expectedText = 'Please select a rating.'
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(mockFetch.fetch).not.toHaveBeenCalled()
    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
  })

  it('shows an error when the user provides feedback text longer than limit', async () => {
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog(1))

    const dialog = await screen.findByRole('dialog')

    const limit = 2000
    const expectedText = `Please keep your feedback within ${limit} characters or less.`
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const textbox = await within(dialog).findByRole('textbox')
    await user.click(textbox)
    await user.paste('a'.repeat(limit + 1))

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(mockFetch.fetch).not.toHaveBeenCalled()
    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
  })

  it('shows an error when sending the feedback to the server returns a not okay response', async () => {
    mockFetch.mockRoute('/github-copilot/feedback', {}, {ok: false})
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog(1))

    const dialog = await screen.findByRole('dialog')

    const expectedText = `An error occurred while submitting your feedback.`
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(mockFetch.fetch).toHaveBeenCalled()
    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
  })

  it('shows an error when sending the feedback to the server returns a rejected promise response', async () => {
    const dialogRef = React.createRef<FeedbackDialogRef>()
    const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

    act(() => dialogRef.current?.openDialog(1))

    const dialog = await screen.findByRole('dialog')

    const expectedText = `An error occurred while submitting your feedback.`
    expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)
    await mockFetch.rejectPendingRequest('/github-copilot/feedback', "I'm sorry, Dave. I'm afraid I can't do that.")

    expect(mockFetch.fetch).toHaveBeenCalled()
    expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
  })
})

describe('user dismisses survey dialog', () => {
  beforeEach(() => {
    jest.spyOn(copilotFeatureFlags, 'copilotChatInterviewSurvey', 'get').mockReturnValue(true)
  })

  describe('by "No thanks" button', () => {
    it('opens feedback dialog', async () => {
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

      act(() => dialogRef.current?.openDialog())

      let dialog = await screen.findByRole('dialog')

      // Look for things identifying the survey dialog
      expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()

      await user.click(within(dialog).getByRole('button', {name: /no, thanks/i}))

      // Look for things identifying the feedback dialog
      dialog = await screen.findByRole('dialog')
      expect(await within(dialog).findByRole('textbox')).toBeInTheDocument()
      expect(await within(dialog).findAllByRole('radio')).toHaveLength(4)
      expect(await within(dialog).findByRole('button', {name: /send/i})).toBeInTheDocument()
    })
  })

  describe('by "Close" button', () => {
    it('closes dialog', async () => {
      const dialogRef = React.createRef<FeedbackDialogRef>()
      const {user} = render(<ConversationFeedbackDialog ref={dialogRef} mode="assistive" />)

      act(() => dialogRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')

      // Look for things identifying the survey dialog
      expect(await within(dialog).findByRole('link', {name: /book a session/i})).toBeInTheDocument()

      await user.click(within(dialog).getByRole('button', {name: /close/i}))

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })
  })
})
