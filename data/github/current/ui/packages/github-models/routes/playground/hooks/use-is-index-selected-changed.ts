import {useCallback} from 'react'
import type {PlaygroundState} from '../../../types'

interface UseHandleIsUseIndexSelectedChangeParams {
  setIsUseIndexSelected: (index: number, isSelected: boolean) => void
  setParametersHasChanges: (index: number, hasChanges: boolean) => void
  position: number
  state: PlaygroundState
}

export const useHandleIsUseIndexSelectedChange = ({
  setIsUseIndexSelected,
  setParametersHasChanges,
  position,
  state,
}: UseHandleIsUseIndexSelectedChangeParams) => {
  return useCallback(
    (isSelected: boolean) => {
      for (const [index] of state.models.entries()) {
        if (state.syncInputs || index === position) {
          setIsUseIndexSelected(index, isSelected)
          setParametersHasChanges(index, true)
        }
      }
    },
    [setIsUseIndexSelected, setParametersHasChanges, position, state.models, state.syncInputs],
  )
}
