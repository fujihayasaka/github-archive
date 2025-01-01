import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotCodeReviewFeedback} from '../CopilotCodeReviewFeedback'

test('renders with feedbackPath', () => {
  const props = {feedbackPath: 'asdf', commentId: '1'}
  render(<CopilotCodeReviewFeedback {...props} />)
  expect(screen.getByTestId('copilot-code-review-feedback-1')).toBeInTheDocument()
})

test('renders with commentUrl', () => {
  const props = {commentUrl: 'https://foo.bar/1', commentId: '1'}
  render(<CopilotCodeReviewFeedback {...props} />)
  expect(screen.getByTestId('copilot-code-review-feedback-1')).toBeInTheDocument()
})

test('fails to render without feedbackPath or commentUrl', () => {
  jest.spyOn(console, 'error').mockImplementation()
  const props = {commentId: '1'}

  render(<CopilotCodeReviewFeedback {...props} />)
  expect(screen.queryByTestId('copilot-code-review-feedback-1')).not.toBeInTheDocument()

  // eslint-disable-next-line no-console
  expect(console.error).toHaveBeenCalled()
})
