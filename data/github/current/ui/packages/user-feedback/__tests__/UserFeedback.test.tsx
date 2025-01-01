import React from 'react'
import {screen, act, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {UserFeedback, type RatingOption, type FeedbackRef} from '../UserFeedback'

const ratingOptions: Array<RatingOption<number>> = [
  {
    name: 'Bad',
    value: 1,
    icon: null,
    color: 'bad',
  },
  {
    name: 'Good',
    value: 2,
    icon: null,
    color: 'good',
  },
]

it('renders closed', async () => {
  const feedbackRef = React.createRef<FeedbackRef<number>>()
  render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} />)

  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})

describe('openDialog', () => {
  it('raises an error if an invalid initial option value is provided', async () => {
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} />)

    expect(() => act(() => feedbackRef.current?.openDialog(0))).toThrow('invalid initial option value')
  })

  it('shows the dialog without selecting an option when no option is provided', async () => {
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} />)

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    act(() => feedbackRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    for (const option of ratingOptions) {
      const ratingButton = await within(dialog).findByRole('radio', {name: option.name})
      expect(ratingButton).not.toBeChecked()
    }
  })

  it('shows the dialog with the provided option selected', async () => {
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} />)

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

    const initOption = ratingOptions[0]!
    act(() => feedbackRef.current?.openDialog(initOption.value))

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toBeInTheDocument()

    let ratingButton = await within(dialog).findByRole('radio', {name: initOption.name})
    expect(ratingButton).toBeChecked()

    for (const option of ratingOptions) {
      if (option.value === initOption.value) {
        continue
      }

      ratingButton = await within(dialog).findByRole('radio', {name: option.name})
      expect(ratingButton).not.toBeChecked()
    }
  })
})

describe('user selects rating', () => {
  it('clears any shown errors', async () => {
    const onSubmit = jest.fn().mockResolvedValue(['error'])
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

    act(() => feedbackRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(await within(dialog).findByText('error')).toBeInTheDocument()

    const firstRatingButton = await within(dialog).findByRole('radio', {name: ratingOptions[0]!.name})
    await user.click(firstRatingButton)

    expect(within(dialog).queryByText('error')).not.toBeInTheDocument()
  })
})

describe('user types feedback', () => {
  it('clears any shown errors', async () => {
    const onSubmit = jest.fn().mockResolvedValue(['error'])
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

    act(() => feedbackRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    expect(await within(dialog).findByText('error')).toBeInTheDocument()

    const textbox = await within(dialog).findByRole('textbox')
    await user.type(textbox, 'This is my feedback')

    expect(within(dialog).queryByText('error')).not.toBeInTheDocument()
  })
})

describe('user submits feedback', () => {
  it('does not show previously entered feedback when dialog is re-opened', async () => {
    const onSubmit = jest.fn().mockResolvedValue([])
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

    const initOption = ratingOptions[0]!
    act(() => feedbackRef.current?.openDialog(initOption.value))

    let dialog = await screen.findByRole('dialog')

    let textbox = await within(dialog).findByRole('textbox')
    await user.type(textbox, 'This is my feedback')

    const submitButton = await within(dialog).findByRole('button', {name: /send/i})
    await user.click(submitButton)

    // The feedback is submitted and the dialog is closed
    expect(onSubmit).toHaveBeenCalledWith(initOption.value, 'This is my feedback')
    expect(dialog).not.toBeInTheDocument()

    // Reopen the dialog
    act(() => feedbackRef.current?.openDialog())

    dialog = await screen.findByRole('dialog')

    for (const option of ratingOptions) {
      const ratingButton = await within(dialog).findByRole('radio', {name: option.name})
      expect(ratingButton).not.toBeChecked()
    }

    textbox = await within(dialog).findByRole('textbox')
    expect(textbox).toHaveValue('')
  })

  describe('onSubmit', () => {
    it('gets called with null when no option is selected', async () => {
      const onSubmit = jest.fn().mockResolvedValue([])
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalledWith(null, '')
    })

    it('gets called with the initial selected option value', async () => {
      const onSubmit = jest.fn().mockResolvedValue([])
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      const initOption = ratingOptions[0]!
      act(() => feedbackRef.current?.openDialog(initOption.value))

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalledWith(initOption.value, '')
    })

    it('gets called with the selected option value', async () => {
      const onSubmit = jest.fn().mockResolvedValue([])
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog(ratingOptions[0]!.value))
      const lastRatingOption = ratingOptions[ratingOptions.length - 1]!
      const lastRatingButton = await screen.findByRole('radio', {name: lastRatingOption.name})
      await user.click(lastRatingButton)

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalledWith(lastRatingOption.value, '')
    })

    it('gets called with user provided feedback text', async () => {
      const onSubmit = jest.fn().mockResolvedValue([])
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')

      const feedback = 'This is my feedback'
      const textbox = await within(dialog).findByRole('textbox')
      await user.type(textbox, feedback)

      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalledWith(null, feedback)
    })

    it('allows the dialog to close if no values are returned', async () => {
      const onSubmit = jest.fn().mockResolvedValue([])
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalled()
      expect(dialog).not.toBeInTheDocument()
    })

    it('causes a generic error to be shown in the dialog when a rejected promise is returned', async () => {
      const onSubmit = jest.fn().mockRejectedValue(undefined)
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')

      const expectedText = 'An error occurred while submitting your feedback.'
      expect(within(dialog).queryByText(expectedText)).not.toBeInTheDocument()

      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalled()
      expect(await within(dialog).findByText(expectedText)).toBeInTheDocument()
    })

    it('causes returned values to be shown as errors in the dialog', async () => {
      const errors = ['Error 1', 'Error 2']
      const onSubmit = jest.fn().mockResolvedValue(errors)
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')

      for (const error of errors) {
        expect(within(dialog).queryByText(error)).not.toBeInTheDocument()
      }

      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onSubmit).toHaveBeenCalled()
      for (const error of errors) {
        expect(await within(dialog).findByText(error)).toBeInTheDocument()
      }
    })

    it('replaces previously shown errors with returned values in the dialog', async () => {
      const errors = ['Error 1', 'Error 2']
      const onSubmit = jest.fn().mockResolvedValueOnce([errors[0]]).mockResolvedValueOnce([errors[1]])
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} />)

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')

      for (const error of errors) {
        expect(within(dialog).queryByText(error)).not.toBeInTheDocument()
      }

      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(await within(dialog).findByText(errors[0]!)).toBeInTheDocument()
      expect(within(dialog).queryByText(errors[1]!)).not.toBeInTheDocument()

      await user.click(submitButton)

      expect(within(dialog).queryByText(errors[0]!)).not.toBeInTheDocument()
      expect(await within(dialog).findByText(errors[1]!)).toBeInTheDocument()
      expect(onSubmit).toHaveBeenCalledTimes(2)
    })
  })

  describe('onClose', () => {
    it('gets called when onSubmit does not return values', async () => {
      const onClose = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} onClose={onClose} />,
      )

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onClose).toHaveBeenCalled()
    })

    it('does not get called when onSubmit returns a rejected promise', async () => {
      const onClose = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback
          ref={feedbackRef}
          options={ratingOptions}
          onSubmit={async () => Promise.reject(new Error('error'))}
          onClose={onClose}
        />,
      )

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onClose).not.toHaveBeenCalled()
    })

    it('does not get called when onSubmit returns values', async () => {
      const onClose = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => ['error']} onClose={onClose} />,
      )

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const submitButton = await within(dialog).findByRole('button', {name: /send/i})
      await user.click(submitButton)

      expect(onClose).not.toHaveBeenCalled()
    })
  })
})

describe('user dismisses dialog', () => {
  it('closes the dialog when the cancel button is clicked', async () => {
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} />)

    act(() => feedbackRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    const cancelButton = await within(dialog).findByRole('button', {name: /cancel/i})
    await user.click(cancelButton)

    expect(dialog).not.toBeInTheDocument()
  })

  it('closes the dialog when esc is pressed', async () => {
    const feedbackRef = React.createRef<FeedbackRef<number>>()
    const {user} = render(<UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} />)

    act(() => feedbackRef.current?.openDialog())

    const dialog = await screen.findByRole('dialog')
    await user.keyboard('{Escape}')

    expect(dialog).not.toBeInTheDocument()
  })

  describe('onSubmit', () => {
    it('does not get called when the cancel button is clicked', async () => {
      const onSubmit = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} onClose={jest.fn()} />,
      )

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const cancelButton = await within(dialog).findByRole('button', {name: /cancel/i})

      await user.click(cancelButton)
      expect(onSubmit).not.toHaveBeenCalled()
    })

    it('does not get called when esc is pressed', async () => {
      const onSubmit = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={onSubmit} onClose={jest.fn()} />,
      )

      act(() => feedbackRef.current?.openDialog())

      await user.keyboard('{Escape}')
      expect(onSubmit).not.toHaveBeenCalled()
    })
  })

  describe('onClose', () => {
    it('gets called when the cancel button is clicked', async () => {
      const onClose = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} onClose={onClose} />,
      )

      act(() => feedbackRef.current?.openDialog())

      const dialog = await screen.findByRole('dialog')
      const cancelButton = await within(dialog).findByRole('button', {name: /cancel/i})

      expect(onClose).not.toHaveBeenCalled()
      await user.click(cancelButton)
      expect(onClose).toHaveBeenCalled()
    })

    it('gets called when esc is pressed', async () => {
      const onClose = jest.fn()
      const feedbackRef = React.createRef<FeedbackRef<number>>()
      const {user} = render(
        <UserFeedback ref={feedbackRef} options={ratingOptions} onSubmit={async () => []} onClose={onClose} />,
      )

      act(() => feedbackRef.current?.openDialog())

      expect(onClose).not.toHaveBeenCalled()
      await user.keyboard('{Escape}')
      expect(onClose).toHaveBeenCalled()
    })
  })
})
