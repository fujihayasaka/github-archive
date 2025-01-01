import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {msw} from '@github-ui/tests/msw'
import {screen, within} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesEnrichedDataPayload} from './utils/mock-data'

describe('ReactCoreExamplesApp EnrichedData Page', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('displays enriched data with deferred data', async () => {
    const embeddedData = getReactCoreExamplesEnrichedDataPayload()

    render(reactCoreExamplesApp, '/_react_core_examples/enriched_data', {embeddedData})

    const issuesTable = await screen.findByTestId('pull-table')

    expect(await within(issuesTable).findAllByRole('row')).toHaveLength(11)
    expect(await within(issuesTable).findAllByText('label')).toHaveLength(10)
  })

  it('displays initial data and warning when request fails', async () => {
    const embeddedData = getReactCoreExamplesEnrichedDataPayload()

    render(reactCoreExamplesApp, '/_react_core_examples/enriched_data', {embeddedData})

    await userEvent.click(await screen.findByLabelText('Show Error State?'))

    const issuesTable = await screen.findByTestId('pull-table')

    expect(await within(issuesTable).findAllByRole('row')).toHaveLength(11)
    expect(within(issuesTable).queryByText('label')).not.toBeInTheDocument()
    expect(await screen.findByText('Failed to load labels. Please try again.')).toBeInTheDocument()
  })
})
