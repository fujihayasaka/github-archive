/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCopilotCodeGuidelineReviewCommentProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders copilot-code-guideline-review-comment partial with SSR', async () => {
  const props = getCopilotCodeGuidelineReviewCommentProps()
  const view = await serverRenderReact({
    name: 'copilot-code-guideline-review-comment',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(/@@ -0,0 \+1,6 @@/)
})
