import ModelInfo from '../../../../components/ModelDetailsSidebar/ModelInfo'
import {usePlaygroundManager} from '../../../../contexts/PlaygroundManagerContext'
import {useSystemPromptChange, useUpdateSystemPrompt} from '../../hooks/use-system-prompt-change'
import {usePlaygroundState} from '../../../../contexts/PlaygroundStateContext'
import {useHandleInputChange} from '../../hooks/use-model-params-change'
import {useHandleJsonSchemaChange, useHandleResponseFormatChange} from '../../hooks/use-response-format-change'
import {useHandleIsUseIndexSelectedChange} from '../../hooks/use-is-index-selected-changed'
import type {ModelState} from '../../../../types'
import {SidebarSelectionOptions} from '../../../../types'
import ModelParameters from './ModelParameters'

interface SidebarContentProps {
  activeTab: SidebarSelectionOptions
  modelState: ModelState
  position: number
  headingLevel?: 'h2' | 'h3'
}

export function SidebarContent({activeTab, headingLevel = 'h3', modelState, position}: SidebarContentProps) {
  const schemaParams = modelState.modelInputSchema?.parameters || []
  const state = usePlaygroundState()
  const {
    setIsUseIndexSelected,
    setSystemPrompt,
    setParametersHasChanges,
    setResponseFormat,
    setParameters,
    setJsonSchema,
  } = usePlaygroundManager()

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

  switch (activeTab) {
    case SidebarSelectionOptions.DETAILS:
      return <ModelInfo headingLevel={headingLevel} model={modelState.catalogData} renderAs="button" />
    case SidebarSelectionOptions.PARAMETERS:
    default:
      return (
        <ModelParameters
          model={modelState}
          handleSystemPromptChange={handleSystemPromptChange}
          handleModelParamsChange={handleModelParamsChange}
          handleResponseFormatChange={handleResponseFormatChange}
          handleIsUseIndexSelectedChange={handleIsUseIndexSelectedChange}
          handleJsonSchemaChange={handleJsonSchemaChange}
          updateSystemPrompt={updateSystemPrompt}
          onSinglePlaygroundView
        />
      )
  }
}
