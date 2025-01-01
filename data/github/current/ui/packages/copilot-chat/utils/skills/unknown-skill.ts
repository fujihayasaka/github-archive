import type {CopilotChatState, Dispatcher} from '../copilot-chat-reducer'
import type {ClientSideSkillDefinition} from '../copilot-chat-types'
import type {ClientSkill} from './client-skill'

export class UnknownClientSkill implements ClientSkill {
  id: string
  name: string
  rawArguments: string
  chatState: CopilotChatState | undefined
  dispatch: Dispatcher | undefined

  constructor(
    id: string,
    name: string,
    rawArguments: string,
    chatState: CopilotChatState | undefined,
    dispatch: Dispatcher | undefined,
  ) {
    this.id = id
    this.name = name
    this.rawArguments = rawArguments
    this.chatState = chatState
    this.dispatch = dispatch
  }

  requiresConfirmation(): boolean {
    return false
  }

  confirmationMessage(): string {
    return 'Unknown function'
  }

  execute() {
    return {ok: true, result: `Unknown function: ${this.name} called with args: ${this.rawArguments}`}
  }

  schema(): ClientSideSkillDefinition {
    return {
      type: 'function',
      function: {
        name: 'unknown-client-skill',
        description: 'This is a fallback skill if the skill is not found',
      },
    }
  }
}
