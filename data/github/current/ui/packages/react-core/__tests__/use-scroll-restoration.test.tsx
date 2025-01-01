import {renderHook, act, waitFor} from '@testing-library/react'
import {useScrollRestoration, installScrollRestoration} from '../use-scroll-restoration'

const fakeRestorationDataForIdentifier = jest.fn().mockImplementation(() => ({
  scrollPosition: {x: 66, y: 33},
}))

jest.mock('@github/turbo', () => ({
  session: {
    history: {
      getRestorationDataForIdentifier: fakeRestorationDataForIdentifier,
      restorationIdentifier: 'whatever',
    },
  },
}))

jest.mock('@github-ui/ssr-utils', () => ({
  ssrSafeLocation: {
    href: 'http://localhost/scroll-position#one',
  },
  ssrSafeWindow: window,
}))

const setWindowLocation = (href: string) => {
  Object.defineProperty(window, 'location', {
    value: {
      href,
    },
    writable: true,
  })
}

describe('useScrollRestoration', () => {
  describe('with `use-scroll-restoration` feature flag enabled', () => {
    beforeEach(() => {
      installScrollRestoration()
    })
    afterEach(() => {
      jest.resetAllMocks()
    })

    it('does not restore scroll position on load', () => {
      renderHook(() => useScrollRestoration())

      expect(window.scrollTo).not.toHaveBeenCalled()
    })

    it('does not restore scroll position if there is no restoration info', () => {
      fakeRestorationDataForIdentifier.mockImplementationOnce(() => undefined)
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(window.scrollTo).not.toHaveBeenCalled()
    })

    it('restores scroll position after popstate to the turbo restoration state', async () => {
      fakeRestorationDataForIdentifier.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(fakeRestorationDataForIdentifier).toHaveBeenCalled()
      await waitFor(() => expect(window.scrollTo).toHaveBeenLastCalledWith(66, 33))
      expect(window.scrollTo).toHaveBeenCalledTimes(1)
    })
  })

  it('only runs installScrollRestoration once', async () => {
    jest.spyOn(window, 'addEventListener')

    installScrollRestoration()
    await waitFor(() => {
      // we need to wait for the async turbo import
      expect(window.addEventListener).toHaveBeenCalledTimes(2)
    })
    installScrollRestoration()
    expect(window.addEventListener).toHaveBeenCalledTimes(2)
  })

  describe('with handling hash routing', () => {
    beforeEach(() => {
      installScrollRestoration()
    })
    afterEach(() => {
      jest.resetAllMocks()
    })

    it('does not restore scroll restoration if the current location and previous location are equal', async () => {
      fakeRestorationDataForIdentifier.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))
      setWindowLocation('http://localhost/scroll-position#one')

      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())
      expect(window.scrollTo).not.toHaveBeenCalled()
    })

    it('restores scroll position if the current location and previous location are different', async () => {
      fakeRestorationDataForIdentifier.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))
      setWindowLocation('http://localhost/scroll-position')

      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())
      await waitFor(() => expect(window.scrollTo).toHaveBeenLastCalledWith(66, 33))
      expect(window.scrollTo).toHaveBeenCalledTimes(1)
    })

    it('correctly handles scroll position if locations change across renders', async () => {
      fakeRestorationDataForIdentifier.mockImplementationOnce(() => ({scrollPosition: {x: 66, y: 33}}))

      setWindowLocation('http://localhost/scroll-position#one')
      expect(window.location.href).toBe('http://localhost/scroll-position#one')

      setWindowLocation('http://localhost/scroll-position')
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(window.location.href).toBe('http://localhost/scroll-position')
      await waitFor(() => expect(window.scrollTo).toHaveBeenCalledWith(66, 33))
      expect(window.scrollTo).toHaveBeenCalledTimes(1)

      fakeRestorationDataForIdentifier.mockImplementationOnce(() => ({scrollPosition: {x: 111, y: 222}}))

      setWindowLocation('http://localhost/scroll-position#two')
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(window.location.href).toBe('http://localhost/scroll-position#two')
      await waitFor(() => expect(window.scrollTo).toHaveBeenLastCalledWith(111, 222))
      expect(window.scrollTo).toHaveBeenCalledTimes(2)

      setWindowLocation('http://localhost/scroll-position#two')
      act(() => window.dispatchEvent(new PopStateEvent('popstate', {})))
      renderHook(() => useScrollRestoration())

      expect(window.location.href).toBe('http://localhost/scroll-position#two')
      await waitFor(() => expect(window.scrollTo).toHaveBeenCalledTimes(2))
      expect(window.scrollTo).toHaveBeenCalledTimes(2)
    })
  })
})
