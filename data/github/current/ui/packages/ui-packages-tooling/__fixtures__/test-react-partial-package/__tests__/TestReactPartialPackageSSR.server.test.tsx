import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {expect, it} from '@github-ui/tests'
import {getTestReactPartialPackageProps} from './utils/mock-data'

// Register with react-core before attempting to render
import '../entry'

it('Renders test-react-partial-package partial with SSR', async () => {
  const props = getTestReactPartialPackageProps()
  const view = await serverRenderReact({
    name: 'test-react-partial-package',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.exampleMessage)
})
