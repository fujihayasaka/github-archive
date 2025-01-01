import {featureFlag} from '@github-ui/feature-flags'
import {afterEach, beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {act, render, screen} from '@testing-library/react'
import {Link, useLocation} from 'react-router-dom'

import {type NavigatorRouteRegistration, TransitionType} from '../app-routing-types'
import {createBrowserHistory} from '../create-browser-history'
import type {EmbeddedData} from '../embedded-data-types'
import {jsonRoute} from '../JsonRoute'
import {NavigatorClientEntry} from '../NavigatorClientEntry'
import {setupUserEvent} from '../test-utils/Render'
import {usePublishPayload} from '../use-publish-payload'
import {useRoutePayload} from '../use-route-payload'

const PageComponent = ({name}: {name: string}) => {
  const payload = useRoutePayload()
  return (
    <>
      <h1>Page {name}</h1>
      <nav>
        <Link to="/a">go to a</Link>
        <Link to="/b">go to b</Link>
        <Link to="/instant">go to instant</Link>
      </nav>
      <pre>{JSON.stringify({payload})}</pre>
    </>
  )
}

const LocationComponent = () => {
  const location = useLocation()

  return <span data-testid="location-hash">{location.hash}</span>
}

const routeA: NavigatorRouteRegistration = jsonRoute({path: '/a', Component: vi.fn(() => <PageComponent name="a" />)})
const routeB: NavigatorRouteRegistration = jsonRoute({path: '/b', Component: vi.fn(() => <PageComponent name="b" />)})
const routeInstant: NavigatorRouteRegistration = jsonRoute({
  path: '/instant',
  Component: vi.fn(() => <PageComponent name="instant" />),
  transitionType: TransitionType.TRANSITION_WHILE_FETCHING,
})
const routeLocation: NavigatorRouteRegistration = jsonRoute({
  path: '/location',
  Component: vi.fn(() => <LocationComponent />),
})
const routes = [routeA, routeB, routeInstant, routeLocation]

let resolveJsonPromise: (data: unknown) => void

vi.mock('@github-ui/soft-nav/utils', () => ({
  inSoftNav: vi.fn(),
  getSoftNavReferrer: vi.fn(),
}))
vi.mock('@github-ui/soft-nav/state', () => ({
  startSoftNav: vi.fn(),
  succeedSoftNav: vi.fn(),
  failSoftNav: vi.fn(),
  renderedSoftNav: vi.fn(),
}))

vi.mock('@github-ui/hydro-analytics', () => ({
  sendPageView: vi.fn(),
}))

vi.mock('@github-ui/stats', () => ({
  sendStats: vi.fn(),
}))

vi.mock('@github-ui/feature-flags')

const renderEntry = async (initialPath: string = routeA.path, embeddedData: EmbeddedData = {payload: null}) => {
  const user = setupUserEvent()
  const window = globalThis.window
  window.history.replaceState({}, '', initialPath)
  // Initial path is set by ruby. Anchors are not sent to the server.
  // Therefore anchors must be set explicitly by the client.
  const {pathname, search, hash} = new URL(initialPath, window?.location.href ?? 'https://github.com')

  const history = createBrowserHistory({window})
  const {key, state} = history.location
  const initialLocation = {
    pathname,
    search,
    hash,
    key,
    state,
  }

  return {
    user,
    ...render(
      <NavigatorClientEntry
        initialLocation={initialLocation}
        history={history}
        appName="test"
        embeddedData={embeddedData}
        routes={routes}
        wasServerRendered={false}
      />,
    ),
  }
}

vi.mock('../use-publish-payload')
const mockedUsePublishPayload = vi.mocked(usePublishPayload)

beforeEach(() => {
  const responsePromise = new Promise(resolve => {
    resolveJsonPromise = resolve
  })
  window.fetch = vi.fn().mockResolvedValueOnce({
    ok: true,
    json: vi.fn(() => responsePromise),
  } as unknown as Response)
  mockedUsePublishPayload.mockReturnValue()

  vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(false)
})

afterEach(() => {
  ;(window.fetch as unknown as ReturnType<typeof vi.fn>).mockClear()
})

describe('Entry', () => {
  describe('initial renders', () => {
    it('renders the correct route', async () => {
      await renderEntry(routeA.path)

      expect(screen.getByText('Page a')).toBeInTheDocument()
      expect(screen.queryByText('Page b')).not.toBeInTheDocument()
    })

    it('initial renders include embedded data without fetching', async () => {
      await renderEntry(routeA.path, {payload: 1})

      expect(screen.getByText('{"payload":1}')).toBeInTheDocument()
      expect(window.fetch).not.toHaveBeenCalled()
    })
  })

  describe('correct initial location', () => {
    const hash = '#MyHash'

    it('uses window hash to set initial location', async () => {
      await renderEntry(routeLocation.path + hash)
      expect(screen.getByTestId('location-hash').textContent).toEqual(hash)
    })
  })

  describe('soft navigations', () => {
    it('fetches and then transitions', async () => {
      const {user} = await renderEntry(routeA.path)

      // Simulate a click on the link to b:

      await user.click(screen.getByText('go to b'))

      expect(window.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/b'),
        expect.objectContaining({
          headers: expect.objectContaining({
            Accept: 'application/json',
          }),
        }),
      )

      // Resolve the mocked fetch response.json:
      await act(async () => {
        resolveJsonPromise({payload: 1})
      })

      // Verify that the new page is shown:
      expect(screen.queryByText('Page a')).not.toBeInTheDocument()
      expect(screen.getByText('Page b')).toBeInTheDocument()
      expect(screen.getByText('{"payload":1}')).toBeInTheDocument()
      expect(screen.getByText('Page b')).toBeInTheDocument()
    })

    it('transitions and then fetches when transtion type is set to before load', async () => {
      const {user} = await renderEntry(routeA.path)

      // Simulate a click on the link to b:
      await user.click(screen.getByText('go to instant'))
      expect(window.fetch).toHaveBeenCalled()

      // Verify that the new page is shown (before the response from the server):
      expect(screen.queryByText('Page a')).not.toBeInTheDocument()
      expect(screen.getByText('Page instant')).toBeInTheDocument()

      // Resolve the mocked fetch response.json:
      await act(async () => {
        resolveJsonPromise({payload: 1})
      })

      // Verify the new page is re-rendered with data
      expect(screen.getByText('Page instant')).toBeInTheDocument()
      expect(screen.getByText('{"payload":1}')).toBeInTheDocument()
    })

    it('includes X-GitHub-App-Type header if send_app_type_header FF is enabled', async () => {
      vi.mocked(featureFlag.isFeatureEnabled).mockReturnValue(true)

      const {user} = await renderEntry(routeA.path)

      // Simulate a click on the link to b:

      await user.click(screen.getByText('go to b'))

      expect(window.fetch).toHaveBeenCalledWith(
        expect.stringContaining('/b'),
        expect.objectContaining({
          headers: expect.objectContaining({
            'X-GitHub-App-Type': 'navigator',
          }),
        }),
      )
    })
  })
})
