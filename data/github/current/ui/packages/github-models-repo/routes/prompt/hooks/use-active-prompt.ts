import {useMemo} from 'react'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {ActivePrompt} from '../prompts'

export default function useActivePrompt(): ActivePrompt {
  const {prompts} = usePromptCompareState()
  const activePrompt = useMemo(() => prompts[0], [prompts])
  return activePrompt
}
