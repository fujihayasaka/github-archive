/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getLicensingEnterpriseCloudDetailsProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders licensing-enterprise-cloud-details partial with SSR', async () => {
  const props = getLicensingEnterpriseCloudDetailsProps()
  const view = await serverRenderReact({
    name: 'licensing-enterprise-cloud-details',
    data: {props},
  })

  // verify ssr was able to render outer wrapper div with id 'licensing-cloud-details'
  expect(view).toMatch(/licensing-cloud-details/)
})
