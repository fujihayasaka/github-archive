import {useMemo} from 'react'
import {useModels} from '../contexts/ModelsContext'
import {findModel} from '../models'
import useActivePrompt from './use-active-prompt'

export default function useActivePromptModel() {
  const activePrompt = useActivePrompt()
  const models = useModels()
  const model = useMemo(() => findModel(activePrompt.model ?? '', models), [activePrompt.model, models])
  return model
}
