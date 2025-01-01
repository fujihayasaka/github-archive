// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {setTitle} from '@github-ui/document-metadata'
import {afterEach, beforeEach, describe, expect, it, type Mock, vi} from '@github-ui/tests'
import {renderHook} from '@testing-library/react'

import type {PageError} from '../app-routing-types'
import type {RouteState} from '../route-state'
import {useTitleManager} from '../use-title-manager'

vi.mock('../use-title-manager', async () => {
  // eslint-disable-next-line @typescript-eslint/consistent-type-imports
  const actual = await vi.importActual<typeof import('../use-title-manager')>('../use-title-manager')
  return {
    __esModule: true,
    ...actual,
    useTitleManager: vi.fn(actual.useTitleManager),
  }
})

vi.mock('@github-ui/document-metadata', async () => {
  // eslint-disable-next-line @typescript-eslint/consistent-type-imports
  const actual = await vi.importActual<typeof import('@github-ui/document-metadata')>('@github-ui/document-metadata')
  return {
    __esModule: true,
    ...actual,
    setTitle: vi.fn(),
  }
})

const currentRouteState: RouteState = {type: 'loaded', data: {payload: ''}, title: 'New title'}

const error: PageError = {
  httpStatus: 500,
  type: 'httpError',
}

describe('useTitleManager', () => {
  beforeEach(() => {
    ;(setTitle as Mock).mockClear()
    ;(useTitleManager as Mock).mockClear()
  })
  afterEach(() => {
    document.body.classList.remove('logged-out')
  })

  it('sets a title for an initial page', () => {
    const location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    renderHook(() => useTitleManager(currentRouteState, null, location))

    expect(useTitleManager).toHaveBeenCalledWith(currentRouteState, null, {
      pathname: '/home',
      search: '',
      hash: '',
      state: null,
      key: '/newPath',
    })

    expect(setTitle).toHaveBeenCalledWith('New title')
  })

  it('appends " · GitHub" to title for logged-out users', () => {
    const location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}
    document.body.classList.add('logged-out')

    renderHook(() => useTitleManager(currentRouteState, null, location))

    expect(setTitle).toHaveBeenCalledWith('New title · GitHub')
  })

  it('sets a title for an error page', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(currentRouteState, error, location))

    location = {pathname: '/another-path', search: '', hash: '', state: null, key: '/newPath'}

    rerender()

    expect(useTitleManager).toHaveBeenCalledWith(currentRouteState, error, {
      pathname: '/home',
      search: '',
      hash: '',
      state: null,
      key: '/newPath',
    })

    expect(useTitleManager).toHaveBeenCalledWith(currentRouteState, error, {
      pathname: '/another-path',
      search: '',
      hash: '',
      state: null,
      key: '/newPath',
    })

    expect(setTitle).toHaveBeenCalledWith('500 Internal server error')
  })

  it('On hash change', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(currentRouteState, null, location))

    location = {pathname: '/newPath', search: '', hash: 'hash', state: null, key: '/newPath'}

    rerender()

    expect(setTitle).toHaveBeenCalledTimes(2)
  })

  it('On non-hash change', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(currentRouteState, null, location))

    location = {pathname: '/newPath', search: '', hash: '', state: null, key: '/newPath'}

    rerender()

    location = {pathname: '/newpage', search: '', hash: 'hash', state: null, key: '/newPath'}

    rerender()

    expect(setTitle).toHaveBeenCalledTimes(3)
  })

  it('On non-hash change and same path name', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(currentRouteState, null, location))

    location = {pathname: '/newPath', search: '', hash: '', state: null, key: '/newPath'}

    rerender()

    location = {pathname: '/newPath', search: 'a search', hash: 'hash', state: null, key: '/newPath'}

    rerender()

    expect(setTitle).toHaveBeenCalledTimes(3)
  })

  it('Error and currentRouteState are null', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(null, null, location))

    location = {pathname: '/newPath', search: '', hash: '', state: null, key: '/newPath'}

    rerender()

    expect(setTitle).not.toHaveBeenCalled()
  })

  it('with a currentRouteState', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(currentRouteState, null, location))

    location = {pathname: '/newPath', search: '', hash: '', state: null, key: '/newPath'}

    rerender()

    expect(setTitle).toHaveBeenCalled()
  })

  it('error has been setup', () => {
    let location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}

    const {rerender} = renderHook(() => useTitleManager(null, error, location))

    location = {pathname: '/newPath', search: '', hash: '', state: null, key: '/newPath'}

    rerender()

    expect(setTitle).toHaveBeenCalled()
  })

  it('does not set a title for a page that has no title configured', () => {
    const location = {pathname: '/home', search: '', hash: '', state: null, key: '/newPath'}
    const routeState: RouteState = {type: 'loaded', data: {payload: ''}, title: ''}

    const {rerender} = renderHook(() => useTitleManager(routeState, null, location))
    rerender()

    expect(setTitle).not.toHaveBeenCalled()
  })
})
