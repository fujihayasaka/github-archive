import {renderHook, act} from '@testing-library/react'
import {usePlanChangeConfirmationDialog} from '../use-plan-change-confirmation-dialog'

describe('usePlanChangeConfirmationDialog', () => {
  test('initializes with null dialog state', () => {
    const {result} = renderHook(() => usePlanChangeConfirmationDialog<{orgId: number}>())

    expect(result.current.dialogState).toEqual({type: null, data: null})
  })

  test('opens a dialog with the correct type and data', () => {
    const {result} = renderHook(() =>
      usePlanChangeConfirmationDialog<{orgId: number; oldPlan: string; newPlan: string}>(),
    )

    act(() => {
      result.current.openDialog('upgrade', {
        orgId: 1,
        oldPlan: 'basic',
        newPlan: 'premium',
      })
    })

    expect(result.current.dialogState).toEqual({
      type: 'upgrade',
      data: {
        orgId: 1,
        oldPlan: 'basic',
        newPlan: 'premium',
      },
    })
  })

  test('closes the dialog and reset the state', () => {
    const {result} = renderHook(() =>
      usePlanChangeConfirmationDialog<{orgId: number; oldPlan: string; newPlan: string}>(),
    )

    act(() => {
      result.current.openDialog('downgrade', {
        orgId: 2,
        oldPlan: 'premium',
        newPlan: 'basic',
      })
    })

    expect(result.current.dialogState).toEqual({
      type: 'downgrade',
      data: {
        orgId: 2,
        oldPlan: 'premium',
        newPlan: 'basic',
      },
    })

    act(() => {
      result.current.closeDialog()
    })

    expect(result.current.dialogState).toEqual({type: null, data: null})
  })
})
