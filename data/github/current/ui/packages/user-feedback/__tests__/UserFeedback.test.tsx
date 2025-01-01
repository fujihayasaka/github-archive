import React from 'react'
import {screen, act} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import type {FeedbackRef} from '../UserFeedback'
import {UserFeedback} from '../UserFeedback'
import {Button} from '@primer/react'

test('Renders the UserFeedback and opens the dialog via openDialog method', async () => {
  const feedbackRef = React.createRef<FeedbackRef>()

  render(<UserFeedback ref={feedbackRef} />)

  await act(async () => {
    feedbackRef.current?.openDialog()
  })

  const dialog = await screen.findByRole('dialog')
  expect(dialog).toBeInTheDocument()
})

test('Renders the UserFeedback and opens the dialog via external button click', async () => {
  const feedbackRef = React.createRef<FeedbackRef>()
  const {user} = render(
    <>
      <Button onClick={() => feedbackRef.current?.openDialog()}>Feedback</Button>
      <UserFeedback ref={feedbackRef} />
    </>,
  )

  const feedbackButton = screen.getByRole('button', {name: /feedback/i})
  expect(feedbackButton).toBeInTheDocument()

  await user.click(feedbackButton)

  const dialog = await screen.findByRole('dialog')
  expect(dialog).toBeInTheDocument()
})
