// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {session} from '@github/turbo'
import {afterEach, beforeEach, describe, expect, it, vi} from '@github-ui/tests'
import {act, renderHook, waitFor} from '@testing-library/react'

import {clear, installScrollRestoration, useScrollRestoration} from '../use-scroll-restoration'

vi.mock('@github/turbo', () => ({
  session: {
    history: {
      getRestorationDataForIdentifier: vi.fn().mockImplementation(() => ({
        scrollPosition: {x: 66, y: 33},
      })),
      restorationIdentifier: 'whatever',
    },
  },
}))

vi.mock('@github-ui/ssr-utils', () => ({
  ssrSafeLocation: {
    href: '/scroll-position#one',
  },
  ssrSafeWindow: window,
}))

const setWindowLocation = (subpath: string) => {
  const url = new URL(subpath, window.location.origin)
  window.history.pushState({}, '', url.toString())
}

const mockedGetRestorationData = vi.mocked(session.history.getRestorationDataForIdentifier)

describe('useScrollRestoration', () => {
  afterEach(() => {
    vi.clearAllMocks()
    clear()
  })

  describe('with `use-scroll-restoration` feature flag enabled', () => {
    beforeEach(async () => {
      vi.spyOn(window, 'scrollTo')
      await installScrollRestoration()
    })

    it('does not restore scroll position on load', () => {
      renderHook(() => useScrollRestoration())

      expect(window.scrollTo).not.toHaveBeenCalled()
    })

    it('does not restore scroll position if there is no restoration info', () => {
      mockedGetRestorationData.mockImplementationOnce(() => ({scrollPosition: undefined}))
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(window.scrollTo).not.toHaveBeenCalled()
    })

    it('restores scroll position after popstate to the turbo restoration state', async () => {
      mockedGetRestorationData.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(mockedGetRestorationData).toHaveBeenCalled()
      await waitFor(() => expect(window.scrollTo).toHaveBeenLastCalledWith(66, 33))
      expect(window.scrollTo).toHaveBeenCalledTimes(1)
    })
  })

  it('only runs installScrollRestoration once', async () => {
    vi.spyOn(window, 'addEventListener')
    vi.spyOn(document, 'addEventListener')

    await installScrollRestoration()
    await waitFor(() => {
      // we need to wait for the async turbo import
      expect(window.addEventListener).toHaveBeenCalledTimes(1)
    })
    expect(document.addEventListener).toHaveBeenCalledTimes(1)
    await installScrollRestoration()
    expect(window.addEventListener).toHaveBeenCalledTimes(1)
    expect(document.addEventListener).toHaveBeenCalledTimes(1)
  })

  describe('with handling hash routing', () => {
    beforeEach(async () => {
      await installScrollRestoration()
    })
    afterEach(() => {
      vi.resetAllMocks()
    })

    it('does not restore scroll restoration if the current location and previous location are equal', async () => {
      mockedGetRestorationData.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))
      setWindowLocation('/scroll-position#one')

      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())
      expect(window.scrollTo).not.toHaveBeenCalled()
    })

    it('restores scroll position if the current location and previous location are different', async () => {
      mockedGetRestorationData.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))
      setWindowLocation('/scroll-position')

      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())
      await waitFor(() => expect(window.scrollTo).toHaveBeenLastCalledWith(66, 33))
      expect(window.scrollTo).toHaveBeenCalledTimes(1)
    })

    it('correctly handles scroll position if locations change across renders', async () => {
      mockedGetRestorationData.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))

      setWindowLocation('/scroll-position#one')
      expect(`${window.location.pathname}${window.location.hash}`).toBe('/scroll-position#one')

      setWindowLocation('/scroll-position')
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(`${window.location.pathname}${window.location.hash}`).toBe('/scroll-position')
      await waitFor(() => expect(window.scrollTo).toHaveBeenCalledWith(66, 33))
      expect(window.scrollTo).toHaveBeenCalledTimes(1)

      mockedGetRestorationData.mockImplementationOnce(() => ({scrollPosition: {x: 111, y: 222}}))

      setWindowLocation('/scroll-position#two')
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(`${window.location.pathname}${window.location.hash}`).toBe('/scroll-position#two')
      await waitFor(() => expect(window.scrollTo).toHaveBeenLastCalledWith(111, 222))
      expect(window.scrollTo).toHaveBeenCalledTimes(2)

      setWindowLocation('/scroll-position#two')
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(`${window.location.pathname}${window.location.hash}`).toBe('/scroll-position#two')
      await waitFor(() => expect(window.scrollTo).toHaveBeenCalledTimes(2))
      expect(window.scrollTo).toHaveBeenCalledTimes(2)
    })
  })
})
