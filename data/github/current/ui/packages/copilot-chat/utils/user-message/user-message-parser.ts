import type {Plugin} from 'unified'

import {agentMentionPattern} from '../agents-helpers'
import {referenceID} from '../copilot-chat-helpers'
import type {CopilotChatAgent, CopilotChatReference} from '../copilot-chat-types'
import {ReferenceMention} from '../reference-mention'
import type {UserMessageNode, UserMessageTree} from './user-message-tree'

interface ParseUserMessageOptions {
  /**
   * All references that are valid to mention in this message. If a `reference-mention` node matches one of these
   * references, it will have the corresponding `mentionedReferenceId` data property set on it.
   */
  references: CopilotChatReference[]
  /** All agents that are valid to mention in this message. */
  agents: CopilotChatAgent[]
}

/**
 * Unified.js plugin that parses a user's message into an abstract syntax tree.
 */
// eslint-disable-next-line func-style
export const userMessageParser: Plugin<[ParseUserMessageOptions], string, UserMessageTree> = function (
  this,
  {references, agents},
) {
  this.parser = function (text: string) {
    const tokens = text.split(/(\s+)/) // splitting with a regex includes all the whitespace as tokens

    const nodes: UserMessageNode[] = []
    for (const [i, token] of tokens.entries()) {
      const agentSlug = i === 0 && agentMentionPattern.exec(token)?.groups?.slug
      const mentionedAgent = agentSlug && agents.find(agent => agent.slug === agentSlug)
      if (mentionedAgent) {
        nodes.push({
          type: 'agent-mention',
          value: token,
          data: {
            mentionedAgent,
          },
        })
        continue
      }

      const referenceMention = ReferenceMention.parse(token)
      const mentionedReference =
        referenceMention && references?.find(r => ReferenceMention.refersTo(referenceMention, r))

      if (referenceMention) {
        nodes.push({
          type: 'reference-mention',
          value: token,
          data: {
            mentionedReferenceId: mentionedReference && referenceID(mentionedReference),
            referenceMention,
          },
        })
        continue
      }

      // Combine adjacent text nodes instead of having a text node for every word
      const lastNode = nodes.at(-1)
      if (lastNode?.type === 'text') lastNode.value += token
      else nodes.push({type: 'text', value: token})
    }

    return {
      type: 'root',
      children: nodes,
    }
  }
}
