import {useCallback} from 'react'
import type {PlaygroundResponseFormat, PlaygroundState} from '../../../types'
import {defaultResponseFormat} from '../../../utils/model-state'

interface UseHandleResponseFormatChangeParams {
  setResponseFormat: (index: number, format: PlaygroundResponseFormat) => void
  setParametersHasChanges: (index: number, hasChanges: boolean) => void
  position: number
  state: PlaygroundState
}

export const useHandleResponseFormatChange = ({
  setResponseFormat,
  setParametersHasChanges,
  position,
  state,
}: UseHandleResponseFormatChangeParams) => {
  return useCallback(
    (selectedResponseFormat: PlaygroundResponseFormat) => {
      for (const [index] of state.models.entries()) {
        if (state.syncInputs || index === position) {
          const newResponseFormat = selectedResponseFormat || defaultResponseFormat
          setResponseFormat(index, newResponseFormat)
          setParametersHasChanges(index, true)
        }
      }
    },
    [setResponseFormat, setParametersHasChanges, position, state.models, state.syncInputs],
  )
}

interface UseHandleJsonSchemaChangeParams {
  state: PlaygroundState
  setJsonSchema: (index: number, jsonSchema: string) => void
  setParametersHasChanges: (index: number, hasChanges: boolean) => void
  position: number
}

export const useHandleJsonSchemaChange = ({
  state,
  setJsonSchema,
  setParametersHasChanges,
  position,
}: UseHandleJsonSchemaChangeParams) => {
  return useCallback(
    (jsonSchema: string) => {
      for (const [index] of state.models.entries()) {
        if (state.syncInputs || index === position) {
          setJsonSchema(index, jsonSchema)
          setParametersHasChanges(index, true)
        }
      }
    },
    [setJsonSchema, setParametersHasChanges, position, state.models, state.syncInputs],
  )
}
