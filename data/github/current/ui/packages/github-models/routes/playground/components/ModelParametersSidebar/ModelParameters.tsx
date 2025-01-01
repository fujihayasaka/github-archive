import {Stack} from '@primer/react'
import {PlaygroundInput} from '../PlaygroundInput'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {ModelResponseFormat} from '../ModelResponseFormat'
import IndexParameter from '../rag/IndexParameter'
import type {ModelInputChangeParams, ModelState, PlaygroundResponseFormat} from '../../../../types'
import {testIdProps} from '@github-ui/test-id-props'
import {supportsJsonSchemaStructuredOutput} from '../../../../utils/model-capability'
import {ModelSystemPrompt} from '../ModelSystemPrompt'
import styles from './ModelParameters.module.css'

export default function ModelParameters({
  model,
  handleModelParamsChange,
  handleSystemPromptChange,
  handleResponseFormatChange,
  handleIsUseIndexSelectedChange,
  handleJsonSchemaChange,
  updateSystemPrompt,
  onSinglePlaygroundView,
}: {
  model: ModelState
  handleModelParamsChange: ({key, value, validate}: ModelInputChangeParams) => void
  handleSystemPromptChange?: (event: React.ChangeEvent<HTMLTextAreaElement>) => void
  handleResponseFormatChange?: (selectedResponseFormat: PlaygroundResponseFormat) => void
  handleIsUseIndexSelectedChange?: (isSelected: boolean) => void
  handleJsonSchemaChange?: (jsonSchema: string) => void
  updateSystemPrompt?: (systemPrompt: string) => void
  onSinglePlaygroundView?: boolean
}) {
  const {modelInputSchema, isUseIndexSelected, parameters, responseFormat, jsonSchema} = model

  const ragFeatureFlag = useFeatureFlag('project_neutron_rag')

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
  const isResponseFormatSupported = model.catalogData.capabilities?.structuredOutput
  const isJsonSchemaSupported = supportsJsonSchemaStructuredOutput(model.catalogData)

  return (
    <Stack {...testIdProps('model-parameters')} gap="normal" className={styles.container}>
      {modelInputSchema?.parameters?.length === 0 &&
        !modelInputSchema?.capabilities?.systemPrompt &&
        !isRAGSupported && (
          <div className="p-3 d-flex flex-column flex-items-center">
            <span className="text-bold">No parameters available</span>
            <p>Currently, this model does not support any parameters for customization.</p>
          </div>
        )}
      {modelInputSchema?.capabilities?.systemPrompt && handleSystemPromptChange && updateSystemPrompt && (
        <ModelSystemPrompt
          systemPrompt={model.systemPrompt}
          handleSystemPromptChange={handleSystemPromptChange}
          updateSystemPrompt={updateSystemPrompt}
          onSinglePlaygroundView={onSinglePlaygroundView}
          showPresets
        />
      )}

      {isResponseFormatSupported && handleResponseFormatChange && handleJsonSchemaChange && (
        <ModelResponseFormat
          responseFormat={responseFormat}
          handleResponseFormatChange={handleResponseFormatChange}
          jsonSchema={jsonSchema}
          handleJsonSchemaChange={handleJsonSchemaChange}
          supportsJsonSchema={isJsonSchemaSupported}
          onSinglePlaygroundView={onSinglePlaygroundView}
        />
      )}

      {ragFeatureFlag && isRAGSupported && handleIsUseIndexSelectedChange && (
        <IndexParameter value={isUseIndexSelected} onChange={handleIsUseIndexSelectedChange} />
      )}
      {/* For each of a model’s inputs, display form components */}
      {(modelInputSchema?.parameters || []).map(parameter => {
        return (
          <PlaygroundInput
            key={parameter.key}
            value={parameters[parameter.key] ?? ''}
            parameter={parameter}
            handleInputChange={handleModelParamsChange}
          />
        )
      })}
    </Stack>
  )
}
