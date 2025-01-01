/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getDependabotRepositoryAccessOrgSettingsProps} from './utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

test('Renders dependabot-repository-access-org-settings partial with SSR', async () => {
  const props = getDependabotRepositoryAccessOrgSettingsProps()
  const view = await serverRenderReact({
    name: 'dependabot-repository-access-org-settings',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('dependabot-repository-access-selector')
  expect(view).toMatch('dependabot-allowed-repository-selector')
})
