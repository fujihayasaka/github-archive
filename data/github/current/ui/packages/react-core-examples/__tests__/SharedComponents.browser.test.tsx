import {withResolvers} from '@github-ui/promise-with-resolvers-polyfill'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {screen, waitFor, within} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesSharedComponentsPayload} from './utils/mock-data'

describe('ReactCoreExamples SharedComponents', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('renders', async () => {
    const embeddedData = getReactCoreExamplesSharedComponentsPayload()
    const userStatus = embeddedData.payload.reactCoreExamplesSharedComponentsRoute.userStatus
    render(reactCoreExamplesApp, '/_react_core_examples/shared_components', {
      embeddedData,
    })

    expect(await screen.findAllByDisplayValue(userStatus.message)).toHaveLength(2)

    expect(document.title).toBe('ReactCoreExamples Shared Components')
  })

  it('handles no user status', async () => {
    const embeddedData = getReactCoreExamplesSharedComponentsPayload()
    // @ts-expect-error setting userStatus to undefined is intentional
    embeddedData.payload.reactCoreExamplesSharedComponentsRoute.userStatus = null
    await render(reactCoreExamplesApp, '/_react_core_examples/shared_components', {
      embeddedData,
    })

    const container = await screen.findByTestId('sharedComponent')
    expect(within(container).getByRole('textbox', {name: 'Set status'})).toHaveValue('')
  })

  it('updates the user status', async () => {
    const embeddedData = getReactCoreExamplesSharedComponentsPayload()
    const userStatus = embeddedData.payload.reactCoreExamplesSharedComponentsRoute.userStatus
    render(reactCoreExamplesApp, '/_react_core_examples/shared_components', {
      embeddedData,
    })

    const container = await screen.findByTestId('sharedComponent')
    const messageInput = within(container).getByRole('textbox', {name: 'Set status'})
    const submitButton = within(container).getByRole('button', {name: 'Set Status'})
    expect(messageInput).toHaveDisplayValue(userStatus.message)

    const {promise, resolve} = withResolvers()
    msw.use(
      http.put('/_react_core_examples/mutations', async () => {
        await promise
        return HttpResponse.json({})
      }),
      http.get('/_react_core_examples/shared_components', () => {
        return HttpResponse.json({
          meta: {}, // meta required due to temporary workaround to wire-format change in `mainQuery`
          payload: {
            reactCoreExamplesSharedComponentsRoute: {
              userStatus: {
                message: 'Refetched Status',
              },
            },
          },
        })
      }),
    )

    await userEvent.clear(messageInput)
    await userEvent.type(messageInput, 'Updated Status')
    await userEvent.click(submitButton)

    expect(submitButton).toHaveAttribute('data-loading', 'true')
    resolve(true)

    await waitFor(() => expect(submitButton).toHaveAttribute('data-loading', 'false'))
  })
})
