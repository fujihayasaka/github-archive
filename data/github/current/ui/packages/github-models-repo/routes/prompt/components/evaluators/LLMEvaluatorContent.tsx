import {TrashIcon} from '@primer/octicons-react'
import {
  Box,
  Button,
  FormControl,
  IconButton,
  Radio,
  RadioGroup,
  SegmentedControl,
  Stack,
  TextInput,
} from '@primer/react'
import {useCallback, useState} from 'react'
import type {RepoModel} from '../../../../types'
import {useModels} from '../../contexts/ModelsContext'
import type {EvaluatorLLM} from '../../evals-sdk/config'
import ModelPicker from '../ModelPicker'
import ParameterSettings, {ParameterSettingsButton, useParameterSettings} from '../ParameterSettings'
import {PromptControl} from './PromptControl'
import {SystemPromptControl} from './SystemPromptControl'

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

  const models = useModels()
  const selectedModel = models.find(m => m.id === e.modelId)

  const onSelectModel = (m: RepoModel) => {
    updateEvaluator({
      ...e,
      modelId: m.id,
      model: m.original_name,
    })
  }

  const setParameters = (params: Record<string, unknown>) => {
    updateEvaluator({
      ...e,
      modelParameters: params,
    })
  }

  const parameterSettingsProps = useParameterSettings(e)

  return (
    <>
      <FormControl disabled={readonly}>
        <FormControl.Label>Model</FormControl.Label>
        <Stack gap="condensed" justify="space-between" direction="horizontal" className="width-full">
          <ModelPicker selectedModel={selectedModel} onSelect={onSelectModel} />
          <ParameterSettingsButton {...parameterSettingsProps} />
        </Stack>
      </FormControl>

      <ParameterSettings {...parameterSettingsProps} setParameters={setParameters} className="ml-2" />

      <SystemPromptControl e={e} readonly={readonly} updateEvaluator={updateEvaluator} />

      <PromptControl e={e} readonly={readonly} updateEvaluator={updateEvaluator} />

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
          <Box key={i} sx={{width: '100%'}}>
            <Stack direction={'horizontal'}>
              <Stack.Item grow className="d-flex">
                <TextInput
                  disabled={readonly}
                  sx={{flexGrow: 1}}
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
                    sx={{width: '75px'}}
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
          </Box>
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
