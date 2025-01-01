import {act, renderHook, waitFor} from '@testing-library/react'

import {TOAST_ANIMATION_LENGTH, ToastType} from '../../../client/components/toasts/types'
import useToastsInternal from '../../../client/components/toasts/use-toasts-internal'

describe('useToastsInternal', () => {
  it('adds a toast to the container with addToast from the hook', () => {
    const {result} = renderHook(useToastsInternal)
    expect(result.current.toasts).toHaveLength(0)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({
        message: 'Changes Saved',
        type: ToastType.success,
      })
    })

    expect(result.current.toasts).toHaveLength(1)
  })

  it('adds only one toast at a time to the container', () => {
    const {result} = renderHook(useToastsInternal)
    expect(result.current.toasts).toHaveLength(0)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({
        message: 'Changes Saved',
        type: ToastType.success,
      })
    })

    expect(result.current.toasts).toHaveLength(1)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({
        message: 'Changes Saved',
        type: ToastType.success,
      })
    })

    expect(result.current.toasts).toHaveLength(1)
  })

  it('respects autodismiss: false', () => {
    const {result} = renderHook(() => useToastsInternal({autoDismiss: false}))

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({message: 'Changes Saved', type: ToastType.success})
    })

    expect(result.current.toasts[0].timeout).toBeUndefined()
  })

  it('adds timeout to new toasts by default', () => {
    const {result} = renderHook(useToastsInternal)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({
        message: 'Changes Saved',
        type: ToastType.success,
      })
    })

    expect(result.current.toasts[0].timeout).toBeDefined()
  })

  it('adds a persisted toast to the container with addPersistedToast', () => {
    const {result} = renderHook(useToastsInternal)
    expect(result.current.persistedToast).toBe(null)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).not.toBe(null)
  })

  it('updates the content of the persisted toast with updatePersistedToast', () => {
    const {result} = renderHook(useToastsInternal)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update pending',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).not.toBe(null)
    expect(result.current.persistedToast!.message).toEqual('Update pending')

    act(() => {
      result.current.updatePersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).not.toBe(null)
    expect(result.current.persistedToast!.message).toEqual('Update in progress')
  })

  it('removes the persisted toast with clearPersistedToast', async () => {
    const timeout = 500
    const {result} = renderHook(() => useToastsInternal({timeout}))

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).not.toBe(null)
    expect(result.current.persistedToast!.message).toEqual('Update in progress')

    act(() => {
      result.current.clearPersistedToast()
    })

    await waitFor(() => expect(result.current.persistedToast).toBe(null), {timeout: timeout + 1000})
  })

  it('does not add a new persisted toast if one is already active', () => {
    const {result} = renderHook(() => useToastsInternal())

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update pending',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).not.toBe(null)
    expect(result.current.persistedToast!.message).toEqual('Update pending')

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast!.message).toEqual('Update pending')
  })

  it('ignores an update to a persisted toast if none is active', () => {
    const {result} = renderHook(() => useToastsInternal())

    expect(result.current.persistedToast).toBe(null)

    act(() => {
      result.current.updatePersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).toBe(null)
  })

  it('replaces the active persistent toast when a new (regular) toast is added', async () => {
    const {result} = renderHook(useToastsInternal)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    expect(result.current.persistedToast).not.toBe(null)
    expect(result.current.persistedToast!.message).toEqual('Update in progress')
    expect(result.current.toasts).toHaveLength(0)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({
        message: 'An unrelated action has occurred',
        type: ToastType.default,
      })
    })

    await waitFor(() => expect(result.current.persistedToast).toBe(null), {timeout: TOAST_ANIMATION_LENGTH + 1000})
    expect(result.current.toasts).toHaveLength(1)
    expect(result.current.toasts[0].message).toEqual('An unrelated action has occurred')
  })

  it('replaces the active (regular) toast when a new persistent toast is added', async () => {
    const {result} = renderHook(useToastsInternal)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addToast({
        message: 'A thing happened',
        type: ToastType.default,
      })
    })

    expect(result.current.toasts).toHaveLength(1)
    expect(result.current.toasts[0].message).toEqual('A thing happened')
    expect(result.current.persistedToast).toBe(null)

    act(() => {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      result.current.addPersistedToast({
        message: 'Update in progress',
        type: ToastType.default,
      })
    })

    await waitFor(() => expect(result.current.toasts).toHaveLength(0), {timeout: TOAST_ANIMATION_LENGTH + 1000})
    expect(result.current.persistedToast).not.toBe(null)
    expect(result.current.persistedToast!.message).toEqual('Update in progress')
  })
})
