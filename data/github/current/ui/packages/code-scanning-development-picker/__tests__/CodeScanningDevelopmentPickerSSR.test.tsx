/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getCodeScanningDevelopmentPickerProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../entry'

test('Renders code-scanning-development-picker partial with SSR', async () => {
  const props = getCodeScanningDevelopmentPickerProps()
  const view = await serverRenderReact({
    name: 'code-scanning-development-picker',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch('Development')
})
