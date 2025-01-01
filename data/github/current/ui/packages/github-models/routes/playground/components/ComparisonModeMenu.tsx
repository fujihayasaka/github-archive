import {Checkbox, FormControl, IconButton} from '@primer/react'
import {TrashIcon} from '@primer/octicons-react'
import {usePlaygroundManager} from '../../../contexts/PlaygroundManagerContext'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import {validateAndFilterParameters} from '../../../utils/model-state'
import type {ModelState} from '../../../types'
import {useSystemPromptChange, useUpdateSystemPrompt} from '../hooks/use-system-prompt-change'
import {useHandleInputChange} from '../hooks/use-model-params-change'
import {useHandleJsonSchemaChange, useHandleResponseFormatChange} from '../hooks/use-response-format-change'
import {useHandleIsUseIndexSelectedChange} from '../hooks/use-is-index-selected-changed'
import ParameterSettingsMenu from '../../prompt/components/ParameterSettingsMenu'

interface ComparisonModeMenuProps {
  modelState: ModelState
  position: number
}

export const ComparisonModeMenu = ({modelState, position}: ComparisonModeMenuProps) => {
  const state = usePlaygroundState()
  const {models, syncInputs} = state
  const {parametersHasChanges} = modelState
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
    <>
      <ParameterSettingsMenu
        model={modelState}
        onOpenChange={(isOpen: boolean) => {
          const {parameters: schema = []} = modelState.modelInputSchema || {}
          if (isOpen || schema.length === 0 || !modelState.parametersHasChanges) return

          // Ensure validation when menu is closed, as it may not have occurred yet
          for (const [index, {modelInputSchema = {}, parameters}] of models.entries()) {
            if (syncInputs || index === position) {
              manager.setParameters(index, validateAndFilterParameters(modelInputSchema.parameters || [], parameters))
            }
          }
        }}
        handleModelParamsChange={handleModelParamsChange}
        handleSystemPromptChange={handleSystemPromptChange}
        handleResponseFormatChange={handleResponseFormatChange}
        handleIsUseIndexSelectedChange={handleIsUseIndexSelectedChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        updateSystemPrompt={updateSystemPrompt}
      >
        <div className="d-flex gap-2 flex-items-center">
          <div className="d-flex">
            {(modelState.modelInputSchema?.parameters?.length !== 0 ||
              modelState.modelInputSchema?.capabilities?.systemPrompt) &&
              parametersHasChanges && (
                <IconButton
                  icon={TrashIcon}
                  as="button"
                  variant="invisible"
                  disabled={!parametersHasChanges}
                  aria-label="Reset to default inputs"
                  onClick={() => {
                    const currentModelDetails = {
                      catalogData: modelState.catalogData,
                      modelInputSchema: modelState.modelInputSchema,
                      gettingStarted: modelState.gettingStarted,
                    }

                    for (const [index] of models.entries()) {
                      if (index === position || syncInputs) {
                        manager.resetParamsAndSystemPrompt(index, currentModelDetails)
                      }
                    }
                  }}
                />
              )}
          </div>
          <form>
            <FormControl>
              <Checkbox value="default" checked={syncInputs} onChange={toggleSyncInputs} />
              <FormControl.Label>Sync chat input and parameters</FormControl.Label>
            </FormControl>
          </form>
        </div>
      </ParameterSettingsMenu>
    </>
  )
}
