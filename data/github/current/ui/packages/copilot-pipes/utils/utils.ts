import type {ChatMessage, Node, NodeValue} from '../types/app'
import {pipeTypesInfo} from '../types/pipe-types'

export const replaceVariablesInNode = (node: Node, nodeMap: Record<string, NodeValue>): Node => {
  const typeInfo = pipeTypesInfo[node.type]
  if (!typeInfo) return node

  const nodeWithVariablesReplaced = {...node}
  for (const field of typeInfo.contentFields) {
    if (!node[field]) continue

    nodeWithVariablesReplaced[field] = replaceIdsInString(
      node[field],
      nodeMap,
      ['code', 'visualize'].includes(node.type),
    )
  }

  return nodeWithVariablesReplaced
}

export function replaceIdsInString(str: string, nodeMap: Record<string, NodeValue>, isInCode = false): string {
  const regex = /{{([\w-]+)(?:\|([\w-]+))?}}/g
  let match

  while ((match = regex.exec(str)) !== null) {
    const id = match[1]
    if (!id) continue

    // if the key is not in the nodeMap, we don't replace it
    if (!Object.keys(nodeMap).includes(id)) continue
    const referencedNodeValue = nodeMap[id]
    const replacementContent = referencedNodeValue

    const isContentString = typeof replacementContent === 'string'
    const replacementString = isContentString && !isInCode ? replacementContent : JSON.stringify(replacementContent)
    str = str.replaceAll(match[0], replacementString)
  }

  return str
}

export async function createNodePromptChat(node: Node): Promise<ChatMessage[]> {
  return [
    {
      role: 'user',
      content: `${node.content}\n\n Respond with just the content, no intro, no explanation, etc.`,
    },
  ]
}

export const getRawNodeIdFromInput = (input: string) => input.split('|')[0]
