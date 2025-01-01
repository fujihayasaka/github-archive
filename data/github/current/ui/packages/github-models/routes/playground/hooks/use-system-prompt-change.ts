import {useCallback} from 'react'
import type {PlaygroundState} from '../../../types'

interface UseSystemPromptChangeParams {
  setSystemPrompt: (index: number, prompt: string) => void
  setParametersHasChanges: (index: number, hasChanges: boolean) => void
  position: number
  state: PlaygroundState
}

export const useSystemPromptChange = ({
  setSystemPrompt,
  setParametersHasChanges,
  position,
  state,
}: UseSystemPromptChangeParams) => {
  return useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      for (const [index] of state.models.entries()) {
        if (state.syncInputs || index === position) {
          setSystemPrompt(index, event.target.value)
          setParametersHasChanges(index, true)
        }
      }
    },
    [setSystemPrompt, setParametersHasChanges, position, state.models, state.syncInputs],
  )
}

interface UseUpdateSystemPromptProps {
  setSystemPrompt: (index: number, prompt: string) => void
  setParametersHasChanges: (index: number, hasChanges: boolean) => void
  position: number
}

export const useUpdateSystemPrompt = ({
  position,
  setSystemPrompt,
  setParametersHasChanges,
}: UseUpdateSystemPromptProps) => {
  return useCallback(
    (systemPrompt: string) => {
      setSystemPrompt(position, systemPrompt)
      setParametersHasChanges(position, true)
    },
    [setSystemPrompt, setParametersHasChanges, position],
  )
}
