import {useCallback} from 'react'
import type {
  ModelInputChangeParams,
  ModelInputSchemaParameter,
  PlaygroundRequestParameters,
  PlaygroundState,
} from '../../../types'
import {validateAndFilterParameters} from '../../../utils/model-state'

interface UseModelParamsChange {
  setParameters: (index: number, params: PlaygroundRequestParameters) => void
  setParametersHasChanges: (index: number, hasChanges: boolean) => void
  schemaParams?: ModelInputSchemaParameter[]
  state: PlaygroundState
  position: number
}

export const useHandleInputChange = ({
  setParameters,
  setParametersHasChanges,
  schemaParams = [],
  state,
  position,
}: UseModelParamsChange) => {
  return useCallback(
    ({key, value, validate}: ModelInputChangeParams) => {
      const updateParameters = (index: number, requestParams: PlaygroundRequestParameters) => {
        const unvalidatedParams = {
          ...requestParams,
          [key]: value,
        }

        const params = validate ? validateAndFilterParameters(schemaParams, unvalidatedParams) : unvalidatedParams

        setParameters(index, params)
        setParametersHasChanges(index, true)
      }

      for (const [index, m] of state.models.entries()) {
        if (state.syncInputs || index === position) {
          updateParameters(index, m.parameters)
        }
      }
    },
    [setParameters, setParametersHasChanges, schemaParams, state, position],
  )
}
