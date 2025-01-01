import {act, renderHook} from '@testing-library/react'

import {useConfirmationDialog} from '../use-confirmation-dialog'

describe('useConfirmationDialog', () => {
  it('should initialize with dialog closed', () => {
    const {result} = renderHook(() => useConfirmationDialog())
    expect(result.current.isDialogOpen).toBe(false)
  })

  it('should open the dialog', () => {
    const {result} = renderHook(() => useConfirmationDialog())
    act(() => {
      result.current.setIsDialogOpen(true)
    })
    expect(result.current.isDialogOpen).toBe(true)
  })

  it('should close the dialog on confirm gesture and call onConfirm', () => {
    const onConfirm = jest.fn()
    const {result} = renderHook(() => useConfirmationDialog(onConfirm))
    act(() => {
      result.current.setIsDialogOpen(true)
      result.current.onDialogClose('confirm')
    })
    expect(result.current.isDialogOpen).toBe(false)
    expect(onConfirm).toHaveBeenCalled()
  })

  it('should close the dialog on cancel gesture without calling onConfirm', () => {
    const onConfirm = jest.fn()
    const {result} = renderHook(() => useConfirmationDialog(onConfirm))
    act(() => {
      result.current.setIsDialogOpen(true)
      result.current.onDialogClose('cancel')
    })
    expect(result.current.isDialogOpen).toBe(false)
    expect(onConfirm).not.toHaveBeenCalled()
  })

  it('should close the dialog on close-button gesture without calling onConfirm', () => {
    const onConfirm = jest.fn()
    const {result} = renderHook(() => useConfirmationDialog(onConfirm))
    act(() => {
      result.current.setIsDialogOpen(true)
      result.current.onDialogClose('close-button')
    })
    expect(result.current.isDialogOpen).toBe(false)
    expect(onConfirm).not.toHaveBeenCalled()
  })

  it('should close the dialog on escape gesture without calling onConfirm', () => {
    const onConfirm = jest.fn()
    const {result} = renderHook(() => useConfirmationDialog(onConfirm))
    act(() => {
      result.current.setIsDialogOpen(true)
      result.current.onDialogClose('escape')
    })
    expect(result.current.isDialogOpen).toBe(false)
    expect(onConfirm).not.toHaveBeenCalled()
  })
})
