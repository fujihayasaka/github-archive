/** @jest-environment node */
import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'
import {getWebcamUploadProps} from '../test-utils/mock-data'

// Register with react-core before attempting to render
import '../entry'

test('Renders webcam-upload partial with SSR', async () => {
  const props = getWebcamUploadProps()
  const view = await serverRenderReact({
    name: 'webcam-upload',
    data: {props},
  })

  // verify ssr was able to render some content from the props
  expect(view).toMatch(props.formFieldId)
})
