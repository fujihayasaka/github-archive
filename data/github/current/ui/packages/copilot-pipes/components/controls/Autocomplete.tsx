import {InlineAutocomplete} from '@github-ui/inline-autocomplete'
import type {ShowSuggestionsEvent, Suggestion} from '@github-ui/inline-autocomplete/types'
import {ActionList, type ActionListItemProps} from '@primer/react'
import {useState, type DetailedHTMLProps, type InputHTMLAttributes, type ReactElement} from 'react'

import {usePipesStateLens} from '../../contexts/PipesStateProvider'
import {currentPipeline} from '../../state/lenses'
import type {Node} from '../../types/app'

const NODE_PREFIX = '@'

function NodeSuggestion({node, ...props}: ActionListItemProps & {node: Node}) {
  return (
    <ActionList.Item {...props} key={node.id}>
      {node.id}
      <ActionList.Description>{node.description}</ActionList.Description>
    </ActionList.Item>
  )
}

export function Autocomplete({
  children,
}: {
  children: ReactElement<DetailedHTMLProps<InputHTMLAttributes<HTMLTextAreaElement>, HTMLTextAreaElement>>
}) {
  const nodes = usePipesStateLens(s => currentPipeline(s)?.nodes ?? [])
  const [suggestions, setSuggestions] = useState<Suggestion[] | null>(null)

  const onShowSuggestions = async ({query}: ShowSuggestionsEvent) => {
    const filteredSuggestions: Suggestion[] = nodes
      .filter(node => node.id.startsWith(query))
      .map(node => ({
        value: `{{${node.id}}}`,
        render: props => <NodeSuggestion node={node} {...props} />,
      }))

    setSuggestions(filteredSuggestions)
  }

  const onHideSuggestions = () => {
    setSuggestions(null)
  }

  return (
    <InlineAutocomplete
      fullWidth
      suggestions={suggestions}
      triggers={[{triggerChar: NODE_PREFIX, keepTriggerCharOnCommit: false, insertSpaceOnCommit: false}]}
      tabInsertsSuggestions={false}
      onHideSuggestions={onHideSuggestions}
      onShowSuggestions={onShowSuggestions}
    >
      {children}
    </InlineAutocomplete>
  )
}
