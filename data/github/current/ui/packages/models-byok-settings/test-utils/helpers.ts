import {render as htmlRender} from '@github-ui/react-core/future/test-utils/render'
import {expect, type Mock} from '@github-ui/tests'
import {screen, waitFor} from '@testing-library/react'
import type {HttpResponse, HttpResponseResolver} from 'msw'
import type {ReactNode} from 'react'

import {modelsByokSettingsAppBuilder} from '../config/app-builder'

export async function waitForStableDialog(name?: string) {
  const dialog = screen.getByRole('dialog', {name})
  expect(dialog).toBeInTheDocument()

  // Wait for the slidein animation to finish
  await waitFor(() => {
    expect(dialog).toBeVisible()
  })

  // TODO: Temporary fix, see: https://github.com/github/web-systems/issues/3331
  for (const el of document.querySelectorAll('[data-position-regular]')) {
    el.setAttribute('data-position-regular', 'center')
  }

  return dialog
}

export function render(component: ReactNode) {
  return htmlRender(modelsByokSettingsAppBuilder.createDataRouterAppFromRoutes([{path: '/', element: component}]), '/')
}

export function setupFlashContainer() {
  if (document.getElementById('js-flash-container')) return
  const el = document.createElement('div')
  el.id = 'js-flash-container'
  document.body.appendChild(el)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function spyRequestJson(spy: Mock<(...args: any[]) => HttpResponse>): HttpResponseResolver {
  expect(spy.getMockImplementation(), 'This mock needs an implementation that returns an HttpResponse').toBeDefined()

  return async ({request}) => {
    const r = request.clone()
    let data = await r.json()
    if (typeof data === 'string') {
      data = JSON.parse(data)
    }
    return spy(data)
  }
}
