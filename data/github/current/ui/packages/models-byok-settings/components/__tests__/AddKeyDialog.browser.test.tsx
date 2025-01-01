import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {page, userEvent} from '@github-ui/tests/browser'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {screen, waitFor} from '@testing-library/react'
import type {ReactNode} from 'react'

import {CurrentOrgProvider} from '../../contexts/CurrentOrgContext'
import {customModelsIndexRoute} from '../../routes/CustomModelsIndex/custom-models-index-route'
import {render as htmlRender, spyRequestJson, waitForStableDialog} from '../../test-utils/helpers'
import {customModelsIndexRouteHandlers, getMockPublicKey} from '../../test-utils/mocks'
import {AddKeyDialog} from '../AddKeyDialog'
import {providerList} from '../providers/Providers'

describe('AddKeyDialog', () => {
  const publicKey = getMockPublicKey()

  beforeEach(async () => {
    await page.viewport(1024, 768)
    msw.resetHandlers()
    msw.use(...customModelsIndexRouteHandlers)
  })

  it('renders the dialog with the correct title', async () => {
    await render(<AddKeyDialog onSuccess={vi.fn()} onCancel={vi.fn()} publicKey={publicKey} />)
    expect(screen.getByText('Add custom key')).toBeInTheDocument()
  })

  it('can cancel the dialog', async () => {
    const onCancel = vi.fn()
    await render(<AddKeyDialog onSuccess={vi.fn()} onCancel={onCancel} publicKey={publicKey} />)
    await waitForStableDialog()
    await userEvent.click(screen.getByRole('button', {name: 'Cancel'}))
    expect(onCancel).toHaveBeenCalled()
  })

  it('shows the empty state for the model selector', async () => {
    await render(<AddKeyDialog onSuccess={vi.fn()} onCancel={vi.fn()} publicKey={publicKey} />)
    expect(screen.getByText(/Add a valid key/)).toBeInTheDocument()
  })

  it('`providerList` is defined with elements', () => {
    // This test is just so that if this array was empty or whatever,
    // the below describe blocks would not run
    expect(Array.isArray(providerList)).toBe(true)
    expect(providerList.length).toBeGreaterThan(0)
  })

  // Tests that should apply to all providers
  for (const provider of providerList) {
    describe(`General provider test (${provider.name})`, () => {
      it('allows selecting a provider', async () => {
        await render(<AddKeyDialog onSuccess={vi.fn()} onCancel={vi.fn()} publicKey={publicKey} />)

        const providerPicker = screen.getByRole('button', {name: 'Provider'})
        expect(providerPicker).toBeInTheDocument()

        await userEvent.click(providerPicker)
        await userEvent.click(screen.getByRole('option', {name: provider.name}))

        expect(providerPicker).toHaveTextContent(provider.name)
      })

      it('submitting an empty form shows validation errors', async () => {
        const onSuccess = vi.fn()
        await render(<AddKeyDialog onSuccess={onSuccess} onCancel={vi.fn()} publicKey={publicKey} />)

        const submitButton = screen.getByRole('button', {name: 'Save'})
        expect(submitButton).toBeInTheDocument()

        // Submit the form without filling it
        await userEvent.click(submitButton)

        // Check for validation errors
        expect(screen.getByText('A name is required')).toBeInTheDocument()
        expect(screen.getByText('An API key is required')).toBeInTheDocument()

        expect(onSuccess).not.toHaveBeenCalled()
      })
    })
  }

  it('shows a general error message on server error', async () => {
    const onSuccess = vi.fn()
    const serverFn = vi.fn().mockImplementation(() => new HttpResponse('Internal Server Error', {status: 500}))
    msw.use(http.post(customModelsIndexRoute.path, spyRequestJson(serverFn)))

    await render(<AddKeyDialog onSuccess={onSuccess} onCancel={vi.fn()} publicKey={publicKey} />)

    const providerPicker = screen.getByRole('button', {name: 'Provider'})
    await userEvent.click(providerPicker)
    await userEvent.click(screen.getByRole('option', {name: 'OpenAI'}))

    await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
    await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

    await userEvent.click(screen.getByRole('button', {name: 'Save'}))

    expect(await screen.findByText('An unexpected error occurred. Please try again later.')).toBeInTheDocument()

    expect(onSuccess).not.toHaveBeenCalled()
    expect(serverFn).toHaveBeenCalledExactlyOnceWith({
      provider: 'openai',
      name: 'Test Key',
      api_key: expect.any(String),
      models: [],
    })
  })

  it('shows a server returned error message', async () => {
    const onSuccess = vi.fn()
    const serverFn = vi.fn().mockImplementation(() => HttpResponse.json({message: 'My server message'}, {status: 500}))
    msw.use(http.post(customModelsIndexRoute.path, spyRequestJson(serverFn)))

    await render(<AddKeyDialog onSuccess={onSuccess} onCancel={vi.fn()} publicKey={publicKey} />)

    const providerPicker = screen.getByRole('button', {name: 'Provider'})
    await userEvent.click(providerPicker)
    await userEvent.click(screen.getByRole('option', {name: 'OpenAI'}))

    await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
    await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

    await userEvent.click(screen.getByRole('button', {name: 'Save'}))

    expect(await screen.findByText('My server message')).toBeInTheDocument()

    expect(onSuccess).not.toHaveBeenCalled()
    expect(serverFn).toHaveBeenCalledExactlyOnceWith({
      provider: 'openai',
      name: 'Test Key',
      api_key: expect.any(String),
      models: [],
    })
  })

  describe('Provider: Azure', () => {
    it('ask for additional fields', async () => {
      const onSuccess = vi.fn()
      const serverFn = vi.fn().mockResolvedValue(HttpResponse.json({name: 'test'}))
      msw.use(http.post(customModelsIndexRoute.path, spyRequestJson(serverFn)))
      await render(<AddKeyDialog onSuccess={onSuccess} onCancel={vi.fn()} publicKey={publicKey} />)

      const providerPicker = screen.getByRole('button', {name: 'Provider'})
      await userEvent.click(providerPicker)
      await userEvent.click(screen.getByRole('option', {name: 'Azure AI'}))

      await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
      await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

      // Check for additional fields
      // TODO: what are these?
      await userEvent.fill(screen.getByLabelText('Deployment URL*'), 'TBD_URL')
      await userEvent.fill(screen.getByLabelText('Model ID*'), 'TBD_MODEL_ID')

      await userEvent.click(screen.getByRole('button', {name: 'Save'}))

      await waitFor(() => expect(onSuccess).toHaveBeenCalledTimes(1))
      expect(serverFn).toHaveBeenCalledExactlyOnceWith({
        provider: 'azureai',
        name: 'Test Key',
        api_key: expect.any(String),
        deployment_url: 'TBD_URL',
        model_id: 'TBD_MODEL_ID',
      })
    })
  })

  describe('Provider: OpenAI', () => {
    it('can submit a valid form', async () => {
      const onSuccess = vi.fn()
      const serverFn = vi.fn().mockResolvedValue(HttpResponse.json({name: 'test'}))
      msw.use(http.post(customModelsIndexRoute.path, spyRequestJson(serverFn)))
      await render(<AddKeyDialog onSuccess={onSuccess} onCancel={vi.fn()} publicKey={publicKey} />)

      const providerPicker = screen.getByRole('button', {name: 'Provider'})
      await userEvent.click(providerPicker)
      await userEvent.click(screen.getByRole('option', {name: 'OpenAI'}))

      await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
      await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

      await userEvent.click(screen.getByRole('button', {name: 'Save'}))

      await waitFor(() => expect(onSuccess).toHaveBeenCalledTimes(1))
      expect(serverFn).toHaveBeenCalledExactlyOnceWith({
        provider: 'openai',
        name: 'Test Key',
        api_key: expect.any(String),
        models: [],
      })
    })
  })

  it('when entering a loading state fields are disabled', async () => {
    const onSuccess = vi.fn()
    const resolveServerRequest = withResolvers<HttpResponse>()
    const serverFn = vi.fn().mockReturnValue(resolveServerRequest.promise)
    msw.use(http.post(customModelsIndexRoute.path, spyRequestJson(serverFn)))
    await render(<AddKeyDialog onSuccess={onSuccess} onCancel={vi.fn()} publicKey={publicKey} />)

    // Fill the form with valid values
    const providerPicker = screen.getByRole('button', {name: 'Provider'})
    await userEvent.click(providerPicker)
    await userEvent.click(screen.getByRole('option', {name: 'OpenAI'}))

    await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
    await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

    await userEvent.click(screen.getByRole('button', {name: 'Save'}))

    // Check that form fields are disabled
    expect(screen.getByRole('button', {name: 'Provider'})).toBeDisabled()
    expect(screen.getByLabelText('Name*')).toBeDisabled()
    expect(screen.getByLabelText('Key*')).toBeDisabled()

    resolveServerRequest.resolve(HttpResponse.json({name: 'test'}))
    await waitFor(() => expect(onSuccess).toHaveBeenCalledTimes(1))
  })
})

async function render(ui: ReactNode) {
  // eslint-disable-next-line testing-library/render-result-naming-convention
  const returns = htmlRender(<CurrentOrgProvider value="my-org">{ui}</CurrentOrgProvider>)
  await waitForStableDialog()
  return returns
}

// Promise.withResolvers shim
// See: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/withResolvers
function withResolvers<T>() {
  let resolve: (v: T) => void
  let reject: (v: unknown) => void

  const promise = new Promise<T>((re, rj) => {
    resolve = re
    reject = rj
  })

  // @ts-expect-error — Promises are created synchronously, these exist by now.
  return {promise, resolve, reject}
}
