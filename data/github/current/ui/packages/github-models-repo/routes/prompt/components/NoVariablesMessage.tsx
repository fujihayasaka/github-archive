import {Blankslate} from '@primer/react/experimental'
import type {RepoModel} from '../../../types'
import {useModelDetailsQuery} from '../hooks/use-model-details-query'

interface NoVariablesMessageProps {
  model: RepoModel | undefined
}

export function NoVariablesMessage({model}: NoVariablesMessageProps) {
  const {data: modelDetails, isLoading} = useModelDetailsQuery(model?.registry, model?.name)
  if (isLoading) return null

  const modelSupportsSystemPrompt = modelDetails?.modelInputSchema?.capabilities?.systemPrompt

  return (
    <Blankslate>
      <Blankslate.Heading>No variables</Blankslate.Heading>
      <Blankslate.Description>
        You can add variables to the {modelSupportsSystemPrompt ? 'user and system prompts' : 'user prompt'} using the{' '}
        <code>{'{{variable_name}}'}</code> syntax.
      </Blankslate.Description>
    </Blankslate>
  )
}
