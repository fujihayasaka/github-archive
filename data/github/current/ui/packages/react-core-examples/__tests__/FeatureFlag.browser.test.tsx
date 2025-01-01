import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {msw} from '@github-ui/tests/msw'
import {screen} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesFeatureFlagRoutePayload} from './utils/mock-data'

describe('ReactCoreExamplesApp Feature Flag Routes', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('displays disabled page when feature flag is off', async () => {
    const embeddedData = getReactCoreExamplesFeatureFlagRoutePayload()

    render(reactCoreExamplesApp, '/_react_core_examples/feature_flag', {embeddedData})

    expect(await screen.findByText('Feature Flag Disabled Page')).toBeInTheDocument()
  })

  it('displays enabled page when feature flag is on', async () => {
    const embeddedData = getReactCoreExamplesFeatureFlagRoutePayload(true)

    render(reactCoreExamplesApp, '/_react_core_examples/feature_flag', {embeddedData})

    expect(await screen.findByText('Welcome To A Feature Flag Enabled Page')).toBeInTheDocument()
  })
})
