/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getOverviewProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

// Mock out use-navigate in SSR tests, see https://github.com/github/web-systems/issues/1809
jest.mock('@github-ui/use-navigate', () => {
  return {
    ...jest.requireActual('@github-ui/use-navigate'),
    useNavigate: () => jest.fn(),
  }
})

test('Renders licensing-copilot-overview partial with SSR', async () => {
  const props = getOverviewProps()
  const view = await serverRenderReact({
    name: 'licensing-copilot-overview',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Copilot')
})
