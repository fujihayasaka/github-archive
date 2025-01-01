/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getModelRepoPromptsAppPayload, getModelRepoPromptsRoutePayload} from '../../../test-utils/mock-data'

// Register with react-core before attempting to render
import '../../../ssr-entry'

test('Renders Comparisons with SSR', async () => {
  const appPayload = getModelRepoPromptsAppPayload()
  const payload = getModelRepoPromptsRoutePayload()
  const view = await serverRenderReact({
    name: 'github-models-repo',
    path: '/:owner/:repo/models/comparisons',
    data: {payload, appPayload},
  })

  expect(view).toMatch('Comparisons')
})
