import type {ModelInputChangeParams, ModelParameterValue} from '@github-ui/github-models'
import {supportsJsonSchemaStructuredOutput} from '@github-ui/github-models/ModelCapability'
import {ModelResponseFormat} from '@github-ui/github-models/ModelResponseFormat'
import {PlaygroundInput} from '@github-ui/github-models/PlaygroundInput'
import {SlidersIcon, XIcon} from '@primer/octicons-react'
import {Button, Heading, IconButton} from '@primer/react'
import {useEffect, useMemo, useState} from 'react'
import type {RepoModel, ResponseFormat} from '../../../types'
import {validateAndFilterParameters} from '../../../utils/model-state'
import {useModels} from '../contexts/ModelsContext'
import {usePromptCompareState} from '../contexts/PromptCompareStateContext'
import type {EvaluatorLLM} from '../evals-sdk/config'
import {useModelDetailsQuery} from '../hooks/use-model-details-query'
import {findModel} from '../models'
import type {PromptConfig} from '../prompts'
import styles from './ParameterSettings.module.css'

type ParameterSettingsProps = {
  model: RepoModel | undefined
  isParametersOpen: boolean
  setIsParametersOpen: (isOpen: boolean) => void
  modelParameters: Record<string, unknown>
  responseFormat: ResponseFormat
  jsonSchema: string
}

type EvaluatorLLMWithModel = EvaluatorLLM & {
  model: string
  responseFormat?: ResponseFormat
  jsonSchema?: string
}

export function useParameterSettings(prompt?: PromptConfig | EvaluatorLLMWithModel): ParameterSettingsProps {
  const {prompts} = usePromptCompareState()
  const activePrompt = prompt || prompts[0]
  const models = useModels()
  const model = useMemo(() => findModel(activePrompt.model ?? '', models), [activePrompt.model, models])

  const [isParametersOpen, setIsParametersOpen] = useState(false)

  useEffect(() => {
    if (model) {
      setIsParametersOpen(false)
    }
  }, [model])

  return {
    model,
    isParametersOpen,
    setIsParametersOpen,
    modelParameters: activePrompt.modelParameters ?? {},
    responseFormat: activePrompt.responseFormat ?? 'text',
    jsonSchema: activePrompt.jsonSchema ?? '',
  }
}

interface ParametersSettingsProps {
  modelParameters: Record<string, unknown>
  model: RepoModel | undefined
  isParametersOpen: boolean
  setIsParametersOpen: (isOpen: boolean) => void
  setParameters: (modelParameters: Record<string, unknown>) => void
  setResponseFormat?: (responseFormat: ResponseFormat) => void
  setJsonSchema?: (jsonSchema: string) => void
  responseFormat?: ResponseFormat
  jsonSchema?: string
  className?: string
}

export default function ParameterSettings({
  modelParameters,
  model,
  isParametersOpen,
  setIsParametersOpen,
  setParameters,
  setResponseFormat,
  setJsonSchema,
  responseFormat = 'text',
  jsonSchema = '',
  className = '',
}: ParametersSettingsProps) {
  const {data: modelDetails} = useModelDetailsQuery(model?.registry, model?.name)

  const handleModelParamsChange = ({key, value, validate}: ModelInputChangeParams) => {
    const unvalidatedParams = {
      ...modelParameters,
      [key]: value,
    }

    const params = validate
      ? validateAndFilterParameters(modelDetails?.modelInputSchema?.parameters || [], unvalidatedParams)
      : unvalidatedParams

    setParameters(params)
  }

  const getDefaultParameter = (key: string) => {
    return modelDetails?.modelInputSchema?.parameters?.find(p => p.key === key)?.default ?? ''
  }

  const isResponseFormatSupported = useMemo(() => {
    return model ? model.capabilities?.structuredOutput : false
  }, [model])

  const isJsonSchemaSupported = useMemo(() => {
    return model ? supportsJsonSchemaStructuredOutput(model) : false
  }, [model])

  return (
    <>
      {isParametersOpen ? (
        <div className={className}>
          <Heading as="h1" className={styles.parametersHeading}>
            Parameters
          </Heading>
          <div className="d-flex flex-column px-3 py-3 border rounded">
            {setResponseFormat && setJsonSchema && isResponseFormatSupported && (
              <div className="d-flex">
                <ModelResponseFormat
                  responseFormat={responseFormat}
                  handleResponseFormatChange={setResponseFormat}
                  jsonSchema={jsonSchema}
                  handleJsonSchemaChange={setJsonSchema}
                  supportsJsonSchema={isJsonSchemaSupported}
                  onSinglePlaygroundView
                />
                <div className="flex-1" />
                <IconButton
                  icon={XIcon}
                  onClick={() => setIsParametersOpen(false)}
                  aria-label="Close parameters settings"
                  variant="invisible"
                />
              </div>
            )}
            {(modelDetails?.modelInputSchema?.parameters || []).map((parameter, index) => (
              <div className="d-flex" key={parameter.key}>
                <div className="flex-1">
                  <PlaygroundInput
                    value={
                      (modelParameters?.[parameter.key] as ModelParameterValue) ?? getDefaultParameter(parameter.key)
                    }
                    parameter={parameter}
                    handleInputChange={handleModelParamsChange}
                  />
                </div>
                {!isResponseFormatSupported && index === 0 && (
                  <IconButton
                    icon={XIcon}
                    onClick={() => setIsParametersOpen(false)}
                    aria-label="Close parameters settings"
                    variant="invisible"
                  />
                )}
              </div>
            ))}
            {modelDetails?.modelInputSchema?.parameters?.length === 0 && (
              <div className="d-flex flex-column">
                <div className="d-flex">
                  <span className="text-bold flex-1">No parameters available</span>
                  <IconButton
                    icon={XIcon}
                    onClick={() => setIsParametersOpen(false)}
                    aria-label="Close parameters settings"
                    variant="invisible"
                  />
                </div>
                <p>Currently, this model does not support any parameters for customization.</p>
              </div>
            )}
          </div>
        </div>
      ) : (
        <></>
      )}
    </>
  )
}

export function ParameterSettingsButton({model, isParametersOpen, setIsParametersOpen}: ParameterSettingsProps) {
  return (
    <Button
      leadingVisual={SlidersIcon}
      className={isParametersOpen ? styles.parametersButtonPressedState : ''}
      onClick={() => setIsParametersOpen(!isParametersOpen)}
      aria-label="Show parameters setting"
      disabled={!model}
    >
      Parameters
    </Button>
  )
}
