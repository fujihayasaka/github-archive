import {visit} from 'unist-util-visit'

import {agentMentionPattern} from '../agents-helpers'
import type {UserMessageTree} from './user-message-tree'

export function getAllMentionedReferenceIds(tree: UserMessageTree) {
  const result = new Set<string>()
  visit(tree, node => {
    if (node.type === 'reference-mention' && node.data.mentionedReferenceId !== undefined)
      result.add(node.data.mentionedReferenceId)
  })
  return result
}

export function hasPotentialAgentMention(messageText: string): boolean {
  return agentMentionPattern.test(messageText.split(/\s/)[0] ?? '')
}
