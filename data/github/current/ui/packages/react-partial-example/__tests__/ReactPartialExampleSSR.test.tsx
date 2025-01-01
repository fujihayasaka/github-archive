/** @jest-environment node */
// Register with react-core before attempting to render
import '../ssr-entry'

import {serverRenderReact} from '@github-ui/ssr-test-utils/server-render'

test('Renders', async () => {
  const view = await serverRenderReact({
    name: 'react-partial-example',
    data: {props: {message: 'Ahlan'}},
  })
  expect(view).toMatchInlineSnapshot(
    '"<div class="css-module-style">Example Partial: <!-- -->Ahlan</div><script type="application/json" id="__PRIMER_DATA_:R0:__">{"resolvedServerColorMode":"day"}</script>"',
  )
})
