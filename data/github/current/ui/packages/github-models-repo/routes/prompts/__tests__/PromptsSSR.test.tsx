/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getModelsRoutePayload} from '../../../test-utils/mock-data'

// Register with react-core before attempting to render
import '../../../ssr-entry'

test('Renders Prompts with SSR', async () => {
  const appPayload = getModelsRoutePayload()
  const view = await serverRenderReact({
    name: 'github-models-repo',
    path: '/:owner/:repo/models/prompts',
    data: {payload: {}, appPayload},
  })

  expect(view).toMatch('prompt.md')
})
