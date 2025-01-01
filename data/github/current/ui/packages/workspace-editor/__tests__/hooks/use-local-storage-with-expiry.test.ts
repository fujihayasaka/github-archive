import {act, renderHook} from '@testing-library/react'

import {useLocalStorageWithExpiry} from '../../hooks/use-local-storage-with-expiry'

beforeEach(() => {
  localStorage.clear()
})

test('it defaults the value to the fallback when localStorage is empty', () => {
  expect(localStorage.getItem('exp:foo')).toBeNull()
  const {result} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 100))
  expect(result.current[0]).toEqual('bar')
})

test('it does not call json.parse when initialized with the fallback', () => {
  const parseSpy = jest.spyOn(JSON, 'parse')
  const {result, rerender} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 100))
  expect(result.current[0]).toEqual('bar')
  // no need to call JSON.parse when initializing with fallback
  expect(parseSpy).toHaveBeenCalledTimes(0)

  rerender()
  expect(parseSpy).toHaveBeenCalledTimes(0)
})

test('it calls json.parse twice on setup, but not on re-render', () => {
  localStorage.setItem('exp:foo', '{"value": "some value"}')
  const parseSpy = jest.spyOn(JSON, 'parse')
  const {result, rerender} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 100))
  expect(result.current[0]).toEqual('some value')
  // no need to call JSON.parse when initializing with fallback
  expect(parseSpy).toHaveBeenCalledTimes(3)

  rerender()
  expect(parseSpy).toHaveBeenCalledTimes(3)
})

test('it ignores the fallback when a value was previously in local storage', () => {
  localStorage.setItem('exp:foo', JSON.stringify({value: 'bar'}))
  const {result} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 100))
  expect(result.current[0]).toEqual('bar')
})

test('it sets the value locally and syncs it to local storage', () => {
  const {result} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 100))
  expect(result.current[0]).toEqual('bar')

  act(() => {
    result.current[1]('not-baz')
  })

  expect(result.current[0]).toEqual('not-baz')
  expect(localStorage.getItem('exp:foo')).toContain('not-baz')
})

test('it avoids tearing', () => {
  const views = Array.from({length: 10}, () => renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 100)))

  for (const view of views) {
    expect(view.result.current[0]).toEqual('bar')
  }

  act(() => {
    views[0]!.result.current[1]('not-bar')
  })

  for (const view of views) {
    expect(view.result.current[0]).toEqual('not-bar')
  }

  expect(localStorage.getItem('exp:foo')).toContain('not-bar')
})

test('it handles storagekey changes', () => {
  localStorage.setItem('exp:foo', `{"value": "baz", "deleteAfter": ${Date.now() + 1000}}`)
  const {result, rerender} = renderHook(({key, fallback}) => useLocalStorageWithExpiry(key, fallback, 100), {
    initialProps: {
      key: 'foo',
      fallback: 'bar',
    },
  })

  expect(result.current[0]).toBe('baz')

  rerender({key: 'not-foo', fallback: 'a new improved fallback'})

  expect(result.current[0]).toBe('a new improved fallback')
})

test('it deletes keys past their expiration', () => {
  jest.useFakeTimers()
  // Add a key that should be deleted if not accessed in the next 1 second
  const {result, rerender} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 1))
  act(() => result.current[1]('not-baz'))
  expect(localStorage.getItem('exp:foo')).not.toBeNull()
  // Advance time
  jest.setSystemTime(Date.now() + 1001)
  // It doesn't clear on re-render, but does on a page load
  rerender()
  expect(localStorage.getItem('exp:foo')).not.toBeNull()
  renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 1))
  expect(localStorage.getItem('exp:foo')).toBeNull()
})

test('defaults to a 30 day expiry', () => {
  jest.useFakeTimers()
  // Add a key that should be deleted if not accessed in the next 1 second
  const {result, rerender} = renderHook(() => useLocalStorageWithExpiry('foo', 'bar'))
  act(() => result.current[1]('not-baz'))
  expect(localStorage.getItem('exp:foo')).not.toBeNull()
  // Advance time
  const thirtyDaysMillis = 30 * 24 * 60 * 60 * 1000
  const expiredTime = Date.now() + thirtyDaysMillis
  jest.setSystemTime(expiredTime - 1)
  // doesn't clear before 30 days
  rerender()
  renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 1))
  expect(localStorage.getItem('exp:foo')).not.toBeNull()

  // clears after 30 days on page load
  jest.setSystemTime(expiredTime + 1)
  rerender()
  expect(localStorage.getItem('exp:foo')).not.toBeNull()
  renderHook(() => useLocalStorageWithExpiry('foo', 'bar', 1))
  expect(localStorage.getItem('exp:foo')).toBeNull()
})
