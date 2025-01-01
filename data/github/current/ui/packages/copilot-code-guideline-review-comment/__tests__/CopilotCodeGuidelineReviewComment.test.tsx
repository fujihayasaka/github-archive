import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotCodeGuidelineReviewComment} from '../CopilotCodeGuidelineReviewComment'
import {getCopilotCodeGuidelineReviewCommentProps} from '../test-utils/mock-data'

test('Renders the CopilotCodeGuidelineReviewComment', () => {
  const props = getCopilotCodeGuidelineReviewCommentProps()
  render(<CopilotCodeGuidelineReviewComment {...props} />)
  expect(screen.getByText(/@@ -0,0 \+1,6 @@/)).toBeInTheDocument()
  expect(screen.getByText(props.comment.body)).toBeInTheDocument()
})
