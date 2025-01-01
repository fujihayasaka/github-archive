import type {CopilotChatState} from '../utils/copilot-chat-reducer'
import type {ClientSideSkillDefinition} from '../utils/copilot-chat-types'
import type {ClientSkill} from '../utils/skills/client-skill'

export function mockSkill(
  requiresConfirmation = false,
  confirmationMessage = '',
  executeResult = {ok: true, result: 'Skill 1 success'},
) {
  return class implements ClientSkill {
    id: string
    name: string
    rawArguments: string
    chatState: CopilotChatState | undefined

    constructor(id: string, name: string, rawArguments: string, chatState?: CopilotChatState) {
      this.id = id
      this.name = name
      this.rawArguments = rawArguments
      this.chatState = chatState
    }

    static schema(): ClientSideSkillDefinition {
      return {
        type: 'function',
        function: {
          name: 'testSkill',
          description: 'Test skill',
          parameters: {
            type: 'object',
            properties: {},
          },
        },
      }
    }

    requiresConfirmation() {
      return requiresConfirmation
    }

    confirmationMessage() {
      return confirmationMessage
    }

    execute() {
      return executeResult
    }
  }
}
