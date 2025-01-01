import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {msw} from '@github-ui/tests/msw'
import {screen} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesRoutePayload} from './utils/mock-data'

describe('ReactCoreExamplesApp', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('can test the registered app', async () => {
    const embeddedData = getReactCoreExamplesRoutePayload()
    render(reactCoreExamplesApp, '/_react_core_examples', {
      embeddedData,
    })

    expect(await screen.findByText(/Welcome @testuser/)).toBeInTheDocument()
  })
})
