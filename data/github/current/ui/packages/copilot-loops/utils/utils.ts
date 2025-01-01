import type {ChatMessage, Node, NodeValue} from '../types/app'

/**
 * This regex captures the node ID, optional path, and optional filter type.
 * Example: {{node1.nested.property|map}}
 *
 * 1. The node ID (e.g. "node1")
 * 2. The path to the property (e.g. "nested.property")
 * 3. Additional processing instructions (e.g. "map") which aren't supported yet
 */
export const getNodeReferenceRegex = () => /{{([\w-]+)(?:\.([.\w-]+))?(?:\|([\w-]+))?}}/g

export const SYSTEM_PROMPT = `Respond with only the content — no introductions, explanations, or extra text.
Only use code blocks when they add semantic value (e.g., mermaid diagrams, specific programming languages), not for general markdown formatting, unless the user explicitly asks for it.`

export async function createNodePromptChat(node: Node): Promise<ChatMessage[]> {
  return [
    {
      role: 'system',
      content: SYSTEM_PROMPT,
    },
    {
      role: 'user',
      content: node.content,
    },
  ]
}

export function stringifyNodeValue(nodeValue: NodeValue): string {
  if (nodeValue === null || nodeValue === undefined) {
    return ''
  }

  if (typeof nodeValue === 'string') {
    return nodeValue
  }

  if (nodeValue && typeof nodeValue === 'object') {
    return JSON.stringify(nodeValue, null, 2)
  }

  if (Array.isArray(nodeValue)) {
    return nodeValue.map(stringifyNodeValue).join('\n')
  }

  return String(nodeValue)
}
