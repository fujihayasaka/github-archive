import {FormControl, Stack, Textarea, SegmentedControl} from '@primer/react'
import {PlaygroundInput} from './PlaygroundInput'
import {useCallback, useRef} from 'react'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {usePlaygroundManager} from '../../../utils/playground-manager'
import {usePlaygroundState} from '../../../contexts/PlaygroundStateContext'
import IndexParameter from './rag/IndexParameter'
import type {ModelInputChangeParams, ModelState, PlaygroundResponseFormat} from '../../../types'
import {defaultResponseFormat, validateAndFilterParameters} from '../../../utils/model-state'
import {testIdProps} from '@github-ui/test-id-props'

export default function ModelParameters({model, position}: {model: ModelState; position: number}) {
  const {modelInputSchema, systemPrompt, isUseIndexSelected, parameters, responseFormat} = model

  const manager = usePlaygroundManager()
  const state = usePlaygroundState()
  const textAreaRef = useRef<HTMLTextAreaElement>(null)
  const inSync = state.syncInputs
  const ragFeatureFlag = useFeatureFlag('project_neutron_rag')
  const structuredOutputsFeatureFlag = useFeatureFlag('project_neutron_structured_outputs')

  //  TODO: Models should specify whether they support RAG or not. For now, we'll hardcode it.
  const modelsSupportingRAG = [
    'Mistral-small',
    'Mistral-large',
    'Mistral-large-2407',
    'Mistral-Nemo',
    'Ministral-3B',
    'gpt-4o',
    'gpt-4o-mini',
    'Cohere-command-r',
    'Cohere-command-r-plus',
    'Cohere-command-r-08-2024',
    'Cohere-command-r-plus-08-2024',
  ]
  const isRAGSupported = modelsSupportingRAG.includes(model.catalogData.name)

  const isResponseFormatSupported = structuredOutputsFeatureFlag && !model.catalogData.name.includes('o1') // currently o1-class models don't support structured outputs
  const supportedResponseFormats: PlaygroundResponseFormat[] = ['text', 'json_object']

  const handleInputChange = ({key, value, validate}: ModelInputChangeParams) => {
    for (const [index, m] of state.models.entries()) {
      if (state.syncInputs || index === position) {
        const unvalidatedParams = {
          ...m.parameters,
          [key]: value,
        }
        const params = validate
          ? validateAndFilterParameters(modelInputSchema?.parameters || [], unvalidatedParams)
          : unvalidatedParams

        manager.setParameters(index, params)
        manager.setParametersHasChanges(index, true)
      }
    }
  }

  const handleSystemPromptChange = useCallback(
    (event: React.ChangeEvent<HTMLTextAreaElement>) => {
      for (const [index] of state.models.entries()) {
        if (inSync || index === position) {
          manager.setSystemPrompt(index, event.target.value)
          manager.setParametersHasChanges(index, true)
        }
      }
    },
    [manager, position, state.models, inSync],
  )

  const handleResponseFormatChange = useCallback(
    (selectedIndex: number) => {
      for (const [index] of state.models.entries()) {
        if (inSync || index === position) {
          const newResponseFormat = supportedResponseFormats[selectedIndex] || defaultResponseFormat
          manager.setResponseFormat(index, newResponseFormat)
          manager.setParametersHasChanges(index, true)
        }
      }
    },
    [manager, position, state.models, inSync],
  )

  const handleIsUseIndexSelectedChange = useCallback(
    (isSelected: boolean) => {
      for (const [index] of state.models.entries()) {
        if (inSync || index === position) {
          manager.setIsUseIndexSelected(index, isSelected)
          manager.setParametersHasChanges(index, true)
        }
      }
    },
    [manager, position, state.models, inSync],
  )

  return (
    <Stack {...testIdProps('model-parameters')} gap="normal" className="p-0 p-md-3">
      {modelInputSchema?.parameters?.length === 0 &&
        !modelInputSchema?.capabilities?.systemPrompt &&
        !isRAGSupported && (
          <div className="p-3 d-flex flex-column flex-items-center">
            <span className="text-bold">No parameters available</span>
            <p>Currently, this model does not support any parameters for customization.</p>
          </div>
        )}
      {modelInputSchema?.capabilities?.systemPrompt && (
        <FormControl>
          <FormControl.Label>System prompt</FormControl.Label>
          <FormControl.Caption>Set the context for the model response.</FormControl.Caption>
          <Textarea
            ref={textAreaRef}
            value={systemPrompt}
            block
            resize="vertical"
            rows={1}
            onChange={handleSystemPromptChange}
            name="systemPrompt"
            style={{height: 120}}
            {...testIdProps('model-parameters-system-prompt')}
          />
        </FormControl>
      )}

      {isResponseFormatSupported && (
        <FormControl>
          <FormControl.Label className="mb-1">Response format</FormControl.Label>
          <FormControl.Caption>Set the format for the model response.</FormControl.Caption>
          <SegmentedControl
            onChange={handleResponseFormatChange}
            aria-label="Response format"
            {...testIdProps('response-format')}
          >
            <SegmentedControl.Button selected={responseFormat === 'text'}>Text</SegmentedControl.Button>
            <SegmentedControl.Button selected={responseFormat === 'json_object'}>JSON</SegmentedControl.Button>
          </SegmentedControl>
        </FormControl>
      )}

      {ragFeatureFlag && isRAGSupported && (
        <IndexParameter value={isUseIndexSelected} onChange={handleIsUseIndexSelectedChange} />
      )}
      {/* For each of a model’s inputs, display form components */}
      {(modelInputSchema?.parameters || []).map(parameter => {
        return (
          <PlaygroundInput
            key={parameter.key}
            value={parameters[parameter.key] ?? ''}
            parameter={parameter}
            handleInputChange={handleInputChange}
          />
        )
      })}
    </Stack>
  )
}
