import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {msw} from '@github-ui/tests/msw'
import {screen, waitFor, within} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesDependentDataPayload} from './utils/mock-data'

describe('ReactCoreExamplesApp DependentData Page', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('displays dependent data and allows navigation', async () => {
    const embeddedData = getReactCoreExamplesDependentDataPayload()
    const {login, avatarUrl} = embeddedData.payload.reactCoreExamplesDependentDataRoute

    render(reactCoreExamplesApp, '/_react_core_examples/dependent_data', {embeddedData})

    expect((await screen.findByAltText(login)).getAttribute('src')).toContain(avatarUrl)
    expect(await screen.findByText(login)).toBeInTheDocument()

    const issuesTable = await screen.findByTestId('issue-table')

    await waitFor(async () => expect(await within(issuesTable).findAllByRole('row')).toHaveLength(11))
  })
})
