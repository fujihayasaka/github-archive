import {render as htmlRender} from '@github-ui/react-core/future/test-utils/render'
import {beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {http, HttpResponse, msw} from '@github-ui/tests/msw'
import {screen, waitFor} from '@testing-library/react'
import {passthrough} from 'msw'

import {modelsByokSettingsApp} from '../../models-byok-settings'
import {setupFlashContainer, spyRequestJson, waitForStableDialog} from '../../test-utils/helpers'
import {customModelsIndexRouteHandlers, mockCustomModelsIndexPayload} from '../../test-utils/mocks'
import type {CustomModelsIndexPayload} from '../../types'
import {customModelsIndexRoute} from '../CustomModelsIndex/custom-models-index-route'

describe('CustomModelsIndex', () => {
  beforeEach(() => {
    msw.resetHandlers(...customModelsIndexRouteHandlers, hack_passthrough())
    setupFlashContainer()
  })

  it('renders', async () => {
    const routePayload = mockCustomModelsIndexPayload()
    await render(routePayload)
    expect(screen.getByRole('heading', {level: 2, name: 'Custom models'})).toBeInTheDocument()
  })

  it('renders the empty state with no custom keys', async () => {
    const routePayload = mockCustomModelsIndexPayload({customKeys: []})
    await render(routePayload)
    expect(screen.getByText(/No custom keys added/)).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Add custom key'})).toBeInTheDocument()
  })

  it('renders the custom models', async () => {
    const routePayload = mockCustomModelsIndexPayload()
    await render(routePayload)
    expect(screen.getByRole('button', {name: 'Add custom key'})).toBeInTheDocument()
    expect(screen.queryByText(/No custom keys added/)).not.toBeInTheDocument()
    expect(screen.getByText('Example OpenAI Key')).toBeInTheDocument()
    expect(screen.getByText('Example MSFT Key')).toBeInTheDocument()
  })

  it('after adding a custom key, the list is refetched', async () => {
    const routePayload = mockCustomModelsIndexPayload()
    const serverRequest = vi.fn()
    msw.use(
      http.get(customModelsIndexRoute.path, ({params}) => {
        serverRequest()
        return HttpResponse.json(
          mockCustomModelsIndexPayload({
            orgDisplayLogin: params.org as string,
          }),
        )
      }),
    )
    await render(routePayload)
    expect(serverRequest).not.toHaveBeenCalled()

    // Fill the add custom key dialog
    await userEvent.click(screen.getByRole('button', {name: 'Add custom key'}))

    await waitForStableDialog('Add custom key')

    await userEvent.fill(screen.getByLabelText('Name*'), 'Test Key')
    await userEvent.fill(screen.getByLabelText('Key*'), 'test-api-key')

    await userEvent.click(screen.getByRole('button', {name: 'Save'}))

    await waitFor(() => expect(serverRequest).toHaveBeenCalledTimes(1))

    const banner = await screen.findByRole('banner', {name: 'Success'})
    expect(banner).toBeInTheDocument()
    expect(screen.getByText(/successfully added/)).toBeInTheDocument()
  })

  it('can toggle a model between enabled and disabled for Copilot', async () => {
    const routePayload = mockCustomModelsIndexPayload()

    const toggleRequest = vi.fn().mockResolvedValue(new HttpResponse(null, {status: 200}))
    msw.use(
      http.get(customModelsIndexRoute.path, () => {
        return HttpResponse.json({
          payload: {
            [customModelsIndexRoute.id]: routePayload,
          },
        })
      }),
      http.put(`/organizations/:org/settings/custom-models/:id`, spyRequestJson(toggleRequest)),
    )

    await render(routePayload)

    await userEvent.click(screen.getByRole('button', {name: /Custom Models/}))

    const modelEnabledButton = screen.getByRole('button', {name: /Enabled/, description: 'o1-mini'})
    await userEvent.click(modelEnabledButton)

    await userEvent.click(screen.getByRole('menuitemcheckbox', {name: 'GitHub Copilot'}))

    await waitFor(() => {
      expect(toggleRequest).toHaveBeenCalledWith({
        copilot_chat_enabled: true,
      })
    })
  })

  it('handles toggle endpoint errors gracefully', async () => {
    const routePayload = mockCustomModelsIndexPayload()

    msw.use(
      http.put(`/organizations/:org/settings/custom-models/:id`, () => {
        return HttpResponse.json(
          {
            message: 'Something bad happened on the server',
          },
          {
            status: 500,
          },
        )
      }),
    )

    await render(routePayload)

    await userEvent.click(screen.getByRole('button', {name: /Custom Models/}))

    const modelEnabledButton = screen.getByRole('button', {name: /Enabled/, description: 'o1-mini'})
    await userEvent.click(modelEnabledButton)

    await userEvent.click(screen.getByRole('menuitemcheckbox', {name: 'GitHub Copilot'}))

    await waitFor(() => {
      expect(screen.getByText('Error: Something bad happened on the server')).toBeInTheDocument()
    })
  })
})

async function render(mainQuery: CustomModelsIndexPayload) {
  // eslint-disable-next-line testing-library/render-result-naming-convention
  const returns = htmlRender(
    modelsByokSettingsApp,
    customModelsIndexRoute.generatePath({org: mainQuery.orgDisplayLogin}),
    {
      embeddedData: {
        appPayload: {
          enabled_features: {github_models_byok: true},
        },
        payload: {
          [customModelsIndexRoute.id]: mainQuery,
        },
      },
    },
  )

  await waitFor(() => {
    expect(screen.getByRole('heading', {level: 2, name: 'Custom models'})).toBeInTheDocument()
  })

  return returns
}

function hack_passthrough() {
  // TODO: useRouteQuery doesnt currently wire up abort signals, so some tests can leak between eachother
  // as msw resolves after a test has finished, but a callback may still fire.
  // Lets just squash the requests until we can fix that
  return http.all('*', () => {
    return passthrough()
  })
}
