import {withResolvers} from '@github-ui/promise-with-resolvers-polyfill'
import {render} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {screen, waitFor, within} from '@testing-library/react'

import {reactCoreExamplesApp} from '../react-core-examples'
import {handlers} from './utils/handlers'
import {getReactCoreExamplesMutationsPayload} from './utils/mock-data'

describe('ReactCoreExamples Mutations', () => {
  beforeEach(() => {
    msw.use(...handlers)
  })

  it('renders', async () => {
    const embeddedData = getReactCoreExamplesMutationsPayload()
    const userStatus = embeddedData.payload.reactCoreExamplesMutationsRoute.userStatus
    render(reactCoreExamplesApp, '/_react_core_examples/mutations', {
      embeddedData,
    })

    const form = await screen.findByTestId('userStatus-form')
    expect(form).toBeInTheDocument()

    expect(within(form).getByDisplayValue(userStatus.message)).toBeInTheDocument()
    expect(document.title).toBe('ReactCoreExamples Mutations')
  })

  it('updates the user status', async () => {
    const embeddedData = getReactCoreExamplesMutationsPayload()
    const userStatus = embeddedData.payload.reactCoreExamplesMutationsRoute.userStatus
    render(reactCoreExamplesApp, '/_react_core_examples/mutations', {
      embeddedData,
    })

    const form = await screen.findByTestId('userStatus-form')
    const messageInput = within(form).getByDisplayValue(userStatus.message)
    const submitButton = within(form).getByRole('button', {name: 'Set Status'})
    const status = await screen.findByTestId('status')
    expect(status).toHaveTextContent(userStatus.message)

    const {promise, resolve} = withResolvers()
    msw.use(
      http.put('/_react_core_examples/mutations', async () => {
        await promise
        return HttpResponse.json({})
      }),
      http.get('/_react_core_examples/mutations', () => {
        return HttpResponse.json({
          meta: {}, // meta required due to temporary workaround to wire-format change in `mainQuery`
          payload: {
            reactCoreExamplesMutationsRoute: {
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
    await waitFor(() => expect(status).toHaveTextContent('Refetched Status'))
  })

  it('handles a failed update', async () => {
    const {promise, resolve} = withResolvers()
    msw.use(
      http.put('/_react_core_examples/mutations', async () => {
        await promise
        return HttpResponse.error()
      }),
    )

    const embeddedData = getReactCoreExamplesMutationsPayload()
    const userStatus = embeddedData.payload.reactCoreExamplesMutationsRoute.userStatus
    render(reactCoreExamplesApp, '/_react_core_examples/mutations', {
      embeddedData,
    })

    const form = await screen.findByTestId('userStatus-form')
    const messageInput = within(form).getByDisplayValue(userStatus.message)
    const submitButton = within(form).getByRole('button', {name: 'Set Status'})
    const status = await screen.findByTestId('status')
    expect(status).toHaveTextContent(userStatus.message)

    await userEvent.clear(messageInput)
    await userEvent.type(messageInput, 'Updated Status')
    await userEvent.click(submitButton)

    expect(submitButton).toHaveAttribute('data-loading', 'true')
    resolve(true)
    await waitFor(() => expect(submitButton).toHaveAttribute('data-loading', 'false'))
    expect(screen.getByText('Failed to update status')).toBeInTheDocument()
    expect(status).toHaveTextContent(userStatus.message)
  })

  it('handles no user status', async () => {
    const embeddedData = getReactCoreExamplesMutationsPayload()
    // @ts-expect-error setting userStatus to undefined is intentional
    embeddedData.payload.reactCoreExamplesMutationsRoute.userStatus = null
    render(reactCoreExamplesApp, '/_react_core_examples/mutations', {
      embeddedData,
    })

    const status = await screen.findByTestId('status')
    expect(status).toHaveTextContent('Your status is: --')
  })
})
