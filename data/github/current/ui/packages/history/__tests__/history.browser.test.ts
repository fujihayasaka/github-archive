import {
  currentState,
  removeUrlHash,
  updateCurrentState,
  updateUrlHash,
  updateSearchParams,
  updateUrl,
  addUrlToHistoryStack,
} from '../history'
import {it, expect, vi, describe} from '@github-ui/tests'

it('currentState always returns an object', () => {
  expect(currentState()).toMatchObject({})

  history.replaceState({foo: 'bar'}, '', location.href)

  expect(currentState()).toMatchObject({foo: 'bar'})
})

it('updateUrl keeps the current history state', () => {
  history.replaceState({foo: 'bar'}, '', location.href)

  updateUrl('/baz')

  expect(currentState()).toMatchObject({foo: 'bar'})
  expect(location.pathname).toBe('/baz')
})

it('updateCurrentState does not change the URL', () => {
  const currentURL = location.href
  updateCurrentState({})

  expect(location.href).toBe(currentURL)
})

it('updateCurrentState keeps all state keys and modifies only the ones passed', () => {
  history.replaceState({appId: 'foo'}, '', location.href)

  updateCurrentState({turboCount: 1})

  expect(currentState()).toMatchObject({appId: 'foo', turboCount: 1})

  updateCurrentState({appId: 'bar'})

  expect(currentState()).toMatchObject({appId: 'bar', turboCount: 1})
})

it('updateSearchParams keeps the current hash', () => {
  history.replaceState({}, '', '#hash')

  const searchParams = new URLSearchParams()
  searchParams.set('foo', 'bar')
  updateSearchParams(searchParams)

  expect(location.search).toBe('?foo=bar')
  expect(location.hash).toBe('#hash')
})

it('updateUrlHash keeps the current search params', () => {
  history.replaceState({}, '', '?foo=bar')

  updateUrlHash('#hash')

  expect(location.search).toBe('?foo=bar')
  expect(location.hash).toBe('#hash')
})

it('updateUrlHash keeps the current pathname', () => {
  const currentLocation = location.pathname

  updateUrlHash('#hash')

  expect(location.pathname).toBe(currentLocation)
  expect(location.hash).toBe('#hash')
})

it('updateUrlHash works without the # prefix', () => {
  history.replaceState({}, '', '?foo=bar')

  updateUrlHash('hash')

  expect(location.search).toBe('?foo=bar')
  expect(location.hash).toBe('#hash')
})

it('removeUrlHash keeps the current search params', () => {
  history.replaceState({}, '', '?foo=bar#hash')

  removeUrlHash()

  expect(location.search).toBe('?foo=bar')
  expect(location.hash).toBe('')
})

it('addUrlToHistoryStack propagates the appId', () => {
  history.replaceState({appId: 'test'}, '', location.href)

  addUrlToHistoryStack('/foo')

  expect(history.state.appId).toBe('test')
})

describe('statechange event', () => {
  it('pushing a state dispatches a statechange event', () => {
    vi.spyOn(window, 'dispatchEvent')

    addUrlToHistoryStack('/foo')

    expect(window.dispatchEvent).toHaveBeenCalledWith(
      new CustomEvent('statechange', {bubbles: false, cancelable: false}),
    )
  })

  it('updating the url dispatches a statechange event', () => {
    vi.spyOn(window, 'dispatchEvent')

    updateUrl('/foo')

    expect(window.dispatchEvent).toHaveBeenCalledWith(
      new CustomEvent('statechange', {bubbles: false, cancelable: false}),
    )
  })

  it('updating the state dispatches a statechange event', () => {
    vi.spyOn(window, 'dispatchEvent')

    updateCurrentState({appId: 'test'})

    expect(window.dispatchEvent).toHaveBeenCalledWith(
      new CustomEvent('statechange', {bubbles: false, cancelable: false}),
    )
  })
})
