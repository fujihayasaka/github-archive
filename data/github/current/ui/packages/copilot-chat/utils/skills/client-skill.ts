import type {CopilotChatState, Dispatcher} from '../copilot-chat-reducer'
import type {ClientSideSkillDefinition} from '../copilot-chat-types'

export interface ClientSkill {
  id: string
  name: string
  rawArguments: string
  chatState?: CopilotChatState
  dispatch?: Dispatcher

  execute(confirmationAccepted?: boolean): {ok: boolean; result: string} | Promise<{ok: boolean; result: string}>
  requiresConfirmation(): boolean
  // Confirmation messages should be provided even if the skill does not require a confirmation
  // in case it is called with a skill that does.
  confirmationMessage(): string
}

export type ClientSkillConstructor = {
  new (
    id: string,
    name: string,
    rawArguments: string,
    chatState?: CopilotChatState,
    dispatcher?: Dispatcher,
  ): ClientSkill
  schema(): ClientSideSkillDefinition
}
