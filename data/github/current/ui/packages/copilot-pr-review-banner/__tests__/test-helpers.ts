import {screen} from '@testing-library/react'
import type {User} from '@github-ui/react-core/test-utils'

export async function clickAskCopilotForReview(user: User) {
  const requestReviewButton = screen.getByText('Ask Copilot to review')
  expect(requestReviewButton).toBeInTheDocument()
  await user.click(requestReviewButton)
}
