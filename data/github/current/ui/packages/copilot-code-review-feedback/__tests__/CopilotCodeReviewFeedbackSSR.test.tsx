/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders copilot-code-review-feedback partial with SSR', async () => {
  const props = {feedbackPath: 'asdf', commentId: '1', feedbackOptions: []}
  const view = await serverRenderReact({
    name: 'copilot-code-review-feedback',
    data: {props},
  })

  expect(view).toContain('Positive Feedback')
})
