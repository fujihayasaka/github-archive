import type {CopilotModel} from '@github-ui/copilot-chat/utils/copilot-chat-types'

export interface CopilotImmersiveLoggedOutPayload {
  models: CopilotModel[]
  promptPath: string
  signInPath: string
  signUpPath: string
}
