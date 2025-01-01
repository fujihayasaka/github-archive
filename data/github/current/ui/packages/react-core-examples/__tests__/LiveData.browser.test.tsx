import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {msw} from '@github-ui/tests/msw'
import {screen} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesLiveDataPayload} from './utils/mock-data'

describe('ReactCoreExamplesApp DependentData Page', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('displays dependent initial data', async () => {
    const embeddedData = getReactCoreExamplesLiveDataPayload()
    const {pull} = embeddedData.payload.reactCoreExamplesLiveDataRoute

    render(reactCoreExamplesApp, '/_react_core_examples/live_data', {embeddedData})

    expect(await screen.findByText(pull.title)).toBeInTheDocument()
  })
})
