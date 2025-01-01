import type {Literal, Parent} from 'unist'

import type {CopilotChatAgent} from '../copilot-chat-types'
import type {ReferenceMention} from '../reference-mention'

interface TextLiteral extends Literal {
  value: string
}

export interface ReferenceMentionNode extends TextLiteral {
  value: string
  type: 'reference-mention'
  data: {
    /**
     * If a matching reference was found in the passed options, this will be the ID of that reference. Otherwise, this
     * will be omitted.
     */
    mentionedReferenceId?: string
    referenceMention: ReferenceMention
  }
}

export interface AgentMentionNode extends TextLiteral {
  value: string
  type: 'agent-mention'
  data: {
    mentionedAgent: CopilotChatAgent
  }
}

interface TextNode extends TextLiteral {
  value: string
  type: 'text'
}

export type UserMessageNode = ReferenceMentionNode | AgentMentionNode | TextNode

interface Root extends Parent {
  type: 'root'
  children: UserMessageNode[]
}

export type UserMessageTree = Root
