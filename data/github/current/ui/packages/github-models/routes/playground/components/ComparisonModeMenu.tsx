import {Checkbox, FormControl} from '@primer/react'
import {usePlaygroundManager} from '../../../contexts/PlaygroundManagerContext'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {validateAndFilterParameters} from '../../../utils/model-state'
import type {ModelState} from '../../../types'
import {useSystemPromptChange, useUpdateSystemPrompt} from '../hooks/use-system-prompt-change'
import {useHandleInputChange} from '../hooks/use-model-params-change'
import {useHandleJsonSchemaChange, useHandleResponseFormatChange} from '../hooks/use-response-format-change'
import {useHandleIsUseIndexSelectedChange} from '../hooks/use-is-index-selected-changed'
import ModelParameters from './ModelParametersSidebar/ModelParameters'
import ModelInfo from '../../../components/ModelDetailsSidebar/ModelInfo'
import {CreatePromptFileButton} from './CreatePromptFileButton'
import type {Repository} from '@github-ui/paths'

interface ComparisonModeMenuProps {
  modelState: ModelState
  position: number
  repository?: Repository
}

export const ComparisonModeMenu = ({modelState, position, repository}: ComparisonModeMenuProps) => {
  const state = usePlaygroundState()
  const {models, syncInputs} = state
  const manager = usePlaygroundManager()
  const schemaParams = modelState.modelInputSchema?.parameters || []
  const {
    setIsUseIndexSelected,
    setSystemPrompt,
    setParametersHasChanges,
    setResponseFormat,
    setParameters,
    setJsonSchema,
  } = manager

  const handleSystemPromptChange = useSystemPromptChange({setSystemPrompt, setParametersHasChanges, position, state})
  const handleModelParamsChange = useHandleInputChange({
    setParameters,
    setParametersHasChanges,
    position,
    state,
    schemaParams,
  })
  const handleResponseFormatChange = useHandleResponseFormatChange({
    setResponseFormat,
    setParametersHasChanges,
    position,
    state,
  })
  const handleIsUseIndexSelectedChange = useHandleIsUseIndexSelectedChange({
    setIsUseIndexSelected,
    setParametersHasChanges,
    position,
    state,
  })
  const updateSystemPrompt = useUpdateSystemPrompt({setSystemPrompt, setParametersHasChanges, position})
  const handleJsonSchemaChange = useHandleJsonSchemaChange({
    state,
    setJsonSchema,
    setParametersHasChanges,
    position,
  })

  const toggleSyncInputs = () => {
    const newSyncInputs = !syncInputs

    if (newSyncInputs && models.length > 1) {
      // We need to ensure the other models have the same parameters as this one
      for (const [index, otherModelState] of models.entries()) {
        if (index === position) continue // Skip the current model

        manager.setModelState(index, {
          ...otherModelState,
          systemPrompt: modelState.systemPrompt,
          isUseIndexSelected: modelState.isUseIndexSelected,
          parameters: validateAndFilterParameters(
            otherModelState.modelInputSchema?.parameters || [],
            modelState.parameters,
          ),
          chatInput: modelState.chatInput,
        })
      }
    }

    manager.setSyncInputs(newSyncInputs)
  }

  return (
    <div className="d-flex height-full min-height-0">
      <div className="border-right overflow-auto flex-1">
        <form className="px-3 pt-3">
          <FormControl>
            <Checkbox value="default" checked={syncInputs} onChange={toggleSyncInputs} />
            <FormControl.Label>Sync chat input and parameters</FormControl.Label>
          </FormControl>
        </form>
        <ModelParameters
          model={modelState}
          handleSystemPromptChange={handleSystemPromptChange}
          handleModelParamsChange={handleModelParamsChange}
          handleResponseFormatChange={handleResponseFormatChange}
          handleIsUseIndexSelectedChange={handleIsUseIndexSelectedChange}
          handleJsonSchemaChange={handleJsonSchemaChange}
          updateSystemPrompt={updateSystemPrompt}
        />

        {repository && (
          <div className="border-top position-sticky p-3 d-flex gap-2 flex-column bottom-0 color-bg-default">
            <CreatePromptFileButton modelState={modelState} repository={repository} />
          </div>
        )}
      </div>
      <div className="overflow-auto flex-1">
        <ModelInfo headingLevel={'h3'} model={modelState.catalogData} renderAs="button" />
      </div>
    </div>
  )
}
