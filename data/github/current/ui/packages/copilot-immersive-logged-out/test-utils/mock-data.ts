import {generateDefaultModel} from '@github-ui/copilot-chat/utils/models'

import type {CopilotImmersiveLoggedOutPayload} from '../copilot-immersive-logged-out-types'
import {PROMPT_PATH, SIGN_IN_PATH, SIGN_UP_PATH} from './helpers'

export const mockCopilotImmersiveLoggedOutPayload: CopilotImmersiveLoggedOutPayload = {
  models: [generateDefaultModel()],
  promptPath: PROMPT_PATH,
  signInPath: SIGN_IN_PATH,
  signUpPath: SIGN_UP_PATH,
}
