/* eslint eslint-comments/no-use: off */

import {renderHook} from '@testing-library/react'
import {useSubscribedHandles} from '../use-subscribed-handles'

describe('useSubscribedHandles', () => {
  it('returns the same handles passed in', () => {
    const target = new EventTarget()
    const handles = {
      foo: jest.fn(),
      bar: jest.fn(),
    }

    const {result} = renderHook(() => useSubscribedHandles(target, handles))

    expect(Object.keys(result.current)).toEqual(['foo', 'bar'])
  })

  it('does not bind listeners when we are not listening', () => {
    const target = new EventTarget()
    const targetSpy = jest.spyOn(target, 'addEventListener')
    const handles = {
      foo: jest.fn(),
    }

    let listen = false

    const {rerender} = renderHook(() => useSubscribedHandles(target, handles, listen))
    expect(targetSpy).toHaveBeenCalledTimes(0)

    listen = true

    rerender()
    expect(targetSpy).toHaveBeenCalledTimes(1)
  })

  it('fails gracefully when changing handles', () => {
    // Note; although the api is designed to be stable, and that handles are to be defined statically.
    // In the event that for-whatever reason they are not, we should not break

    const target = new EventTarget()
    const foo = jest.fn()
    const handles = {foo}

    const {result, rerender} = renderHook(() => useSubscribedHandles(target, handles))
    expect(Object.keys(result.current)).toEqual(['foo'])

    delete (handles as any).foo

    rerender()

    // Would still be foo, because the public api is only derived once
    expect(Object.keys(result.current)).toEqual(['foo'])

    expect(() => {
      result.current.foo()
    }).not.toThrow()

    // Because our handles fn no longer has `foo` in it, this would never have ran
    expect(foo).toHaveBeenCalledTimes(0)
  })

  it('calls the other handle when both have the same target', () => {
    const target = new EventTarget()
    const handle1 = jest.fn()
    const handle2 = jest.fn()

    renderHook(() => useSubscribedHandles(target, {foo: handle1}, true))
    const {result} = renderHook(() => useSubscribedHandles(target, {foo: handle2}, true))

    result.current.foo()

    expect(handle1).toHaveBeenCalledTimes(1)
    // There is a subtlety here, if we did not check if the event came from its own hook
    // we'd have run the calling hook's handle twice. Once from the invocation, and then again when the event arrived.
    expect(handle2).toHaveBeenCalledTimes(1)
  })

  it('allows different targets to not interfere', () => {
    const handle1 = jest.fn()
    const handle2 = jest.fn()

    const {result: result1} = renderHook(() => useSubscribedHandles(new EventTarget(), {foo: handle1}, true))
    const {result: result2} = renderHook(() => useSubscribedHandles(new EventTarget(), {foo: handle2}, true))

    result1.current.foo()

    expect(handle1).toHaveBeenCalledTimes(1)
    expect(handle2).toHaveBeenCalledTimes(0)

    result2.current.foo()

    expect(handle1).toHaveBeenCalledTimes(1)
    expect(handle2).toHaveBeenCalledTimes(1)
  })

  it('exceptions in handles should not fire events', () => {
    const target = new EventTarget()
    const targetSpy = jest.spyOn(target, 'dispatchEvent')
    const handle = jest.fn(() => {
      throw new Error('custom error')
    })

    const handles = {
      handle,
    }

    const {result} = renderHook(() => useSubscribedHandles(target, handles, true))
    renderHook(() => useSubscribedHandles(target, handles, true))

    expect(() => {
      result.current.handle()
    }).toThrow('custom error')

    expect(handle).toHaveBeenCalledTimes(1)
    expect(targetSpy).toHaveBeenCalledTimes(0)
  })
})
