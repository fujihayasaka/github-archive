/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

// Register with react-core before attempting to render
import '../../ssr-entry'

import featuresCopilotPagePayload from '../fixtures/routes/FeaturesCopilotPage/indexPagePayload'

test('Renders CopilotIndex with SSR', async () => {
  const view = await serverRenderReact({
    name: 'landing-pages',
    path: '/features/copilot',
    data: {
      payload: featuresCopilotPagePayload,
    },
  })

  // verify Hero
  expect(view).toMatch('GitHub Copilot')
  expect(view).toMatch('The AI editor for everyone')

  // verify Features
  expect(view).toMatch('Features')

  // verify Pricing plans
  expect(view).toMatch('Pricing')
  expect(view).toMatch('Free')
  expect(view).toMatch('Business')
  expect(view).toMatch('19')
  expect(view).toMatch('Enterprise')
  expect(view).toMatch('39')
  expect(view).toMatch('Pro')
  expect(view).toMatch('10')

  // verify FAQs
  expect(view).toMatch('Get the most out of GitHub Copilot')
})
