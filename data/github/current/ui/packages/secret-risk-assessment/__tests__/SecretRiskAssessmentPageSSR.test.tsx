/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getSecretRiskAssessmentPageRoutePayload} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders SecretRiskAssessmentPage with SSR', async () => {
  const routePayload = getSecretRiskAssessmentPageRoutePayload({hasAssessment: false})
  const view = await serverRenderReact({
    name: 'secret-risk-assessment',
    path: '/orgs/:org/security/assessments',
    data: {payload: routePayload},
  })

  // verify ssr was able to render some content from the payload
  expect(view).toMatch('Find secrets exposed in your organization')
})
