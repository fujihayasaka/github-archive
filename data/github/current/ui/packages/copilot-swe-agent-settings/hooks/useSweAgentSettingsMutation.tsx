import {useCallback, useReducer, useRef} from 'react'
import {useCopilotSweAgentSettingsMutation} from './use-fetchers'
import rawValidate from '../validateMcpSchema'

type FieldStatus = {status: 'error' | 'success'; message: string}
type Action = {type: 'NEW_VALUE'; value: string} | {type: 'ERROR'; message: string} | {type: 'SUCCESS'; message: string}

type State = {
  stableValue: string
  currentValue: string | null
  fieldStatus: FieldStatus | null
}

const validate = rawValidate as typeof rawValidate & {
  errors?: Array<{instancePath: string; message?: string}>
}

function validateMcpJson(input: string): {valid: boolean; message?: string} {
  let parsed
  try {
    parsed = JSON.parse(input)
  } catch {
    return {valid: false, message: 'Input must be valid JSON.'}
  }

  const isValid = validate(parsed)

  if (!isValid) {
    const errorMessages = (validate.errors || []).map(err => `${err.instancePath || ''} ${err.message}`).join('; ')
    return {valid: false, message: `Schema validation failed: ${errorMessages}`}
  }

  return {valid: true}
}

const reducer: React.Reducer<State, Action> = (state, action) => {
  switch (action.type) {
    case 'NEW_VALUE':
      return {...state, currentValue: action.value, fieldStatus: null}
    case 'ERROR':
      return {...state, fieldStatus: {status: 'error', message: action.message}}
    case 'SUCCESS':
      return {
        ...state,
        stableValue: state.currentValue ?? state.stableValue,
        currentValue: null,
        fieldStatus: {status: 'success', message: action.message},
      }
  }
}

export function useSweAgentSettingsMutation(endpoint: string, initialValue: string) {
  const [state, dispatch] = useReducer(reducer, {
    stableValue: initialValue,
    currentValue: null,
    fieldStatus: null,
  })

  const currentValue = useRef(state.stableValue)
  currentValue.current = state.currentValue ?? state.stableValue

  const [save] = useCopilotSweAgentSettingsMutation<{mcp_configuration: unknown}, {message: string}>(endpoint, 'PUT')

  const onChange = useCallback((value: string) => {
    dispatch({type: 'NEW_VALUE', value})
  }, [])

  const onSave = useCallback(() => {
    const result = validateMcpJson(currentValue.current)
    if (!result.valid) {
      dispatch({type: 'ERROR', message: result.message ?? 'Invalid input'})
      return
    }

    save({
      payload: {mcp_configuration: currentValue.current},
      onComplete(data, status) {
        if (status === 200) {
          dispatch({type: 'SUCCESS', message: data?.message ?? 'Saved successfully'})
        } else {
          dispatch({type: 'ERROR', message: data?.message ?? 'Failed to save.'})
        }
      },
      onError(_e) {
        dispatch({type: 'ERROR', message: 'Unexpected error occurred while saving.'})
      },
    })
  }, [save])

  return {
    value: currentValue.current,
    fieldStatus: state.fieldStatus,
    onChange,
    onSave,
  }
}
