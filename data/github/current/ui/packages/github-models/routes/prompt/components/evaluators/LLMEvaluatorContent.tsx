import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {TrashIcon} from '@primer/octicons-react'
import {
  Button,
  FormControl,
  IconButton,
  Radio,
  RadioGroup,
  SegmentedControl,
  Stack,
  Textarea,
  TextInput,
} from '@primer/react'
import {useCallback, useEffect, useState, type FormEvent} from 'react'
import type {EvaluatorLLM} from '../../evals-sdk/config'
import ModelPicker from '../ModelPicker'
import type {ModelDetails, ModelInputChangeParams, ModelState} from '../../../../types'
import {getModelState, validateAndFilterParameters} from '../../../../utils/model-state'
import ParameterSettingsMenu from '../ParameterSettingsMenu'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useQuery} from '@github-ui/react-query'
import type {Model} from '@github-ui/marketplace-common'
import {useModelDetailsQuery} from '../../hooks/use-model-details-query'

export type LLMEvaluatorContentProps = {
  e: EvaluatorLLM
  readonly: boolean
  updateEvaluator: (evaluator: EvaluatorLLM) => void
}

const ChoiceMode = {
  PassFail: 'passFail',
  Score: 'score',
} as const

type ChoiceMode = (typeof ChoiceMode)[keyof typeof ChoiceMode]

export function validateLLMEvaluator(e: EvaluatorLLM): string | null {
  if (!e.prompt) {
    return 'Prompt is required'
  }

  if (!e.modelId) {
    return 'Model is required'
  }

  if (e.choices.length === 0) {
    return 'At least one choice is required'
  }

  if (e.choices.some(c => c.choice === '')) {
    return 'All choices must have a value'
  }

  if (e.choices.every(c => c.score === 0)) {
    return 'At least one choice must have a score > 0'
  }

  return null
}

export function LLMEvaluatorContent({e, readonly, updateEvaluator}: LLMEvaluatorContentProps) {
  const [choiceMode, setChoiceMode] = useState<ChoiceMode>(() => {
    // Heuristic to determine initial choice mode
    if (e.choices.length > 2) {
      return ChoiceMode.Score
    }

    // Default to pass/fail
    return ChoiceMode.PassFail
  })

  const removeChoice = useCallback(
    (index: number) => {
      updateEvaluator({
        ...e,
        choices: e.choices.filter((_, i) => i !== index),
      })
    },
    [e, updateEvaluator],
  )

  const addChoice = useCallback(() => {
    updateEvaluator({
      ...e,
      choices: [
        ...e.choices,
        {
          choice: '',
          score: 0,
        },
      ],
    })
  }, [e, updateEvaluator])

  const setChoiceScore = useCallback(
    (index: number, score: number) => {
      updateEvaluator({
        ...e,
        choices: [
          ...e.choices.slice(0, index),
          {
            choice: e.choices[index]!.choice,
            score,
          },
          ...e.choices.slice(index + 1),
        ],
      })
    },
    [e, updateEvaluator],
  )
  const setChoiceChoice = useCallback(
    (index: number, choice: string) => {
      updateEvaluator({
        ...e,
        choices: [
          ...e.choices.slice(0, index),
          {
            ...e.choices[index]!,
            choice,
          },
          ...e.choices.slice(index + 1),
        ],
      })
    },
    [e, updateEvaluator],
  )

  const handlePromptChange = useCallback(
    (evt: FormEvent<HTMLTextAreaElement>) => {
      updateEvaluator({
        ...e,
        prompt: evt.currentTarget.value,
      })
    },
    [e, updateEvaluator],
  )

  const handleSystemPromptChange = useCallback(
    (evt: FormEvent<HTMLTextAreaElement>) => {
      updateEvaluator({
        ...e,
        systemPrompt: evt.currentTarget.value || undefined,
      })
    },
    [e, updateEvaluator],
  )

  // TODO: Make this a re-usable component
  const [variableSuggestions, setVariableSuggestions] = useState<Suggestion[]>([])
  const onShowSuggestions = useCallback((_event: ShowSuggestionsEvent) => {
    // TODO: Get this from evals state, or separate Variables UI
    setVariableSuggestions(['{{prompt}}', '{{input}}', '{{expected}}', '{{completion}}'])
  }, [])
  const onHideSuggestions = useCallback(() => {
    setVariableSuggestions([])
  }, [])

  // TODO: CS: Do not allow access for now
  const restrictedModels: string[] = []

  const [modelState, setModelState] = useState<ModelState>({} as ModelState)
  const {data: models} = useQuery<Model[]>({
    queryKey: ['github-models', 'models'],
    initialData: [],
    async queryFn() {
      const res = await verifiedFetchJSON('/marketplace/models')
      if (!res.ok) throw new Error(await res.text())
      return res.json()
    },
  })

  const selectedModel: Model = models?.find(m => m.id === e.modelId) || ({} as Model)

  const {data: modelDetails, isFetching: isFetchingModelDetails} = useModelDetailsQuery(
    selectedModel?.registry,
    selectedModel?.name,
  )

  const onSelectModel = (m: Model, mDetails: ModelDetails) => {
    updateEvaluator({
      ...e,
      modelId: m.id,
    })

    setModelState(getModelState(mDetails))
  }

  const handleModelParamsChange = ({key, value, validate}: ModelInputChangeParams) => {
    const unvalidatedParams = {
      ...modelState.parameters,
      [key]: value,
    }

    const schema = modelState.modelInputSchema?.parameters

    const params =
      validate && schema !== undefined ? validateAndFilterParameters(schema, unvalidatedParams) : unvalidatedParams

    updateEvaluator({
      ...e,
      modelParameters: params,
    })

    setModelState({...modelState, parameters: params})
  }

  useEffect(() => {
    if (isFetchingModelDetails || Object.keys(modelState).length > 0) {
      return
    }

    if (modelDetails) {
      setModelState({
        ...getModelState(modelDetails),
        ...(e.modelParameters ? {parameters: e.modelParameters} : {}),
      })
    }
  }, [isFetchingModelDetails, e.modelParameters, modelDetails])

  return (
    <>
      <FormControl disabled={readonly}>
        <FormControl.Label>Model</FormControl.Label>
        <div className="d-flex flex-row">
          <ModelPicker modelId={e.modelId} onSelect={onSelectModel} restrictedModels={restrictedModels} />
          <ParameterSettingsMenu
            model={modelState}
            handleModelParamsChange={handleModelParamsChange}
            iconSize="medium"
            className="ml-2"
          />
        </div>
      </FormControl>

      <FormControl disabled={readonly} className="mb-3">
        <FormControl.Label>System prompt</FormControl.Label>
        <Textarea
          value={e.systemPrompt}
          resize="vertical"
          placeholder="Optional system prompt to use when prompting the model"
          block
          onInput={handleSystemPromptChange}
          rows={2}
          style={{height: '50px'}}
        />
      </FormControl>

      <FormControl required disabled={readonly} className="mb-3">
        <FormControl.Label>Prompt</FormControl.Label>
        <InlineAutocomplete
          fullWidth
          tabInsertsSuggestions
          triggers={[
            {
              triggerChar: '{{',
              keepTriggerCharOnCommit: false,
            },
          ]}
          suggestions={variableSuggestions}
          onShowSuggestions={onShowSuggestions}
          onHideSuggestions={onHideSuggestions}
        >
          <Textarea
            value={e.prompt}
            resize="vertical"
            placeholder="Enter your prompt. Connect to your dataset and the model output with {{variables}}"
            block
            onInput={handlePromptChange}
            rows={4}
            style={{height: '150px'}}
          />
        </InlineAutocomplete>
      </FormControl>

      <RadioGroup className="flex-row" name="choiceMode" onChange={selected => setChoiceMode(selected! as ChoiceMode)}>
        <RadioGroup.Label>Mode</RadioGroup.Label>
        <Stack direction="horizontal">
          <FormControl disabled={readonly}>
            <Radio value={ChoiceMode.PassFail} checked={choiceMode === ChoiceMode.PassFail} />
            <FormControl.Label>Pass/Fail</FormControl.Label>
          </FormControl>
          <FormControl disabled={readonly}>
            <Radio value={ChoiceMode.Score} checked={choiceMode === ChoiceMode.Score} />
            <FormControl.Label>Scores</FormControl.Label>
          </FormControl>
        </Stack>
      </RadioGroup>

      <FormControl required disabled={readonly}>
        <FormControl.Label>Choices</FormControl.Label>
        {e.choices.map((c, i) => (
          // eslint-disable-next-line @eslint-react/no-array-index-key
          <div key={i} className="width-full">
            <Stack direction={'horizontal'}>
              <Stack.Item grow className="d-flex">
                <TextInput
                  disabled={readonly}
                  className="flex-1"
                  placeholder="Enter a choice"
                  value={c.choice}
                  onInput={evt => setChoiceChoice(i, evt.currentTarget.value)}
                />
              </Stack.Item>
              {choiceMode === ChoiceMode.Score ? (
                <FormControl disabled={readonly}>
                  <FormControl.Label visuallyHidden>Score</FormControl.Label>
                  <TextInput
                    type="number"
                    style={{width: '75px'}}
                    placeholder="Score"
                    value={c.score}
                    onInput={evt => setChoiceScore(i, parseFloat(evt.currentTarget.value))}
                  />
                </FormControl>
              ) : (
                <SegmentedControl aria-label="Choice value">
                  <SegmentedControl.Button
                    disabled={readonly}
                    selected={c.score === 1}
                    onClick={() => setChoiceScore(i, 1)}
                  >
                    Pass
                  </SegmentedControl.Button>
                  <SegmentedControl.Button
                    disabled={readonly}
                    selected={c.score === 0}
                    onClick={() => setChoiceScore(i, 0)}
                  >
                    Fail
                  </SegmentedControl.Button>
                </SegmentedControl>
              )}
              <IconButton
                disabled={readonly}
                aria-label="Remove choice"
                icon={TrashIcon}
                variant="invisible"
                onClick={() => removeChoice(i)}
              />
            </Stack>
          </div>
        ))}
        {!readonly && (
          <Button size="small" onClick={addChoice}>
            Add choice
          </Button>
        )}
      </FormControl>
    </>
  )
}
