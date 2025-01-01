import {ModelPickerDesign} from '@github-ui/copilot-chat/components/ModelPicker'
import type {CopilotChatModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useAppContext} from '../../contexts/AppContextProvider'

interface ModelPickerProps {
  onUpdateModel: (model: string) => void
  selectedModelName: string
}

export function ModelPicker({onUpdateModel, selectedModelName}: ModelPickerProps) {
  const {availableModels} = useAppContext()
  const selectedModel = availableModels?.find(model => model.id === selectedModelName)

  const handleUpdateModel = (model: CopilotChatModel) => {
    onUpdateModel(model.id)
  }

  if (!availableModels || !selectedModel) return null

  return (
    <ModelPickerDesign
      models={availableModels}
      selectedModel={selectedModel}
      onModelPicked={handleUpdateModel}
      disabled={false}
      type={'global'}
      variant={'default'}
    />
  )
}
