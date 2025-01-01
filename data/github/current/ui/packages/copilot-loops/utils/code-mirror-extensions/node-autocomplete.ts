import {type CompletionContext, type CompletionResult, autocompletion, type Completion} from '@codemirror/autocomplete'
import type {Node} from '../../types/app'

/**
 * Creates a CodeMirror extension that provides autocompletion for pipeline nodes
 * when the '@' character or '{{' is typed
 */
export function createNodeAutocompleteExtension(getPipelineNodes: () => Node[], nodeId?: string) {
  return [
    autocompletion({
      override: [async (context: CompletionContext) => nodeAutocompleteSource(context, getPipelineNodes, nodeId)],
      icons: false,
      defaultKeymap: true,
    }),
  ]
}

/**
 * The source function for generating node completion suggestions
 */
async function nodeAutocompleteSource(
  context: CompletionContext,
  getPipelineNodes: () => Node[],
  nodeId?: string,
): Promise<CompletionResult | null> {
  // Find if we're after the '@' character
  const atWordBefore = context.matchBefore(/@\w*/)

  // Find if we're after the '{{' characters
  const curlyWordBefore = context.matchBefore(/\{\{\w*/)

  const wordBefore = atWordBefore || curlyWordBefore
  if (!wordBefore) return null

  // If at the beginning of a word with no explicit trigger, don't show suggestions
  if (wordBefore.from === wordBefore.to && !context.explicit) return null

  const nodes = getPipelineNodes()

  const query = atWordBefore
    ? wordBefore.text.slice(1) // Remove '@' prefix
    : wordBefore.text.slice(2) // Remove '{{' prefix

  const filteredNodes = nodes.filter(node => node.id.toLowerCase().includes(query.toLowerCase()) && node.id !== nodeId)
  const completions: Completion[] = filteredNodes.map(node => ({
    label: node.title,
    detail: node.id,
    apply: `{{${node.id}}}`,
    boost: 1,
    type: 'variable',
  }))

  return {
    from: wordBefore.from,
    options: completions,
    filter: false,
  }
}
