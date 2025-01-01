import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {expect, it} from '@github-ui/tests'
import {getCustomSignupContentProps} from './utils/mock-data'

// Register with react-core before attempting to render
import '../ssr-entry'

it('Renders custom-signup-content partial with SSR', async () => {
  const props = getCustomSignupContentProps()
  const view = await serverRenderReact({
    name: 'custom-signup-content',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.contentfulContent.entry.fields.heading)
})
