import type {CopilotChatState, Dispatcher} from '../copilot-chat-reducer'
import type {ClientSideSkillDefinition} from '../copilot-chat-types'
import type {ClientSkill} from './client-skill'

// Add additional locations with union as needed
type InternalLocation = 'workbench'
interface NavigateInternallyParams {
  location: InternalLocation
  reasoning: string
}

const LOCATION_MAP = {
  workbench: true,
}

export class NavigateInternallySkill implements ClientSkill {
  id: string
  name: string
  rawArguments: string
  chatState: CopilotChatState | undefined
  dispatch?: Dispatcher

  // TODO: Types are a little whacky for some reason in the constructor (chatState = optional)
  constructor(id: string, name: string, rawArguments: string, chatState?: CopilotChatState, dispatch?: Dispatcher) {
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
    return 'Navigate to the specified location'
  }

  static schema(): ClientSideSkillDefinition {
    const toolDescription = `
    This tool is used to redirect the user to a handful of internal locations that have been predefined. Only the predefined list of locations will be allowed, and any other location will be rejected and cause an error.

    Locations are defined as [slug]: [description]. Use the slug when calling this tool.

    Locations:
    - workbench: A specialized location for helping the user with creating, building, testing, and running code, websites and more. This area should be preferred for any situation where the user wants to build an app, website, or do any sort of extensive coding.
    `

    return {
      type: 'function',
      function: {
        name: 'navigate-internally',
        description: toolDescription,
        parameters: {
          type: 'object',
          required: ['location', 'reasoning'],
          properties: {
            location: {
              description: 'The location slug to navigate the user.',
              type: 'string',
              enum: ['workbench'],
            },
            reasoning: {
              type: 'string',
              description: `The reasoning for why this task is a good candidate for the location. We will display this to the user for confirmation.

                This field should be formatted as follows: "We think this would be a good task for [location] [because] <reasoning>."
                `,
            },
          },
        },
      },
    }
  }

  execute() {
    try {
      const functionArguments: NavigateInternallyParams = JSON.parse(this.rawArguments)
      // Get threadId from state
      const threadId = this.chatState?.selectedThreadID

      if (!threadId) {
        return {
          ok: false,
          result: 'No active thread found. Cannot redirect.',
        }
      }

      const pluginInfo = LOCATION_MAP[functionArguments.location]
      if (!pluginInfo) {
        return {
          ok: false,
          result: `Location ${functionArguments.location} is not valid.`,
        }
      }

      switch (functionArguments.location) {
        case 'workbench': {
          const lastUserMessage = this.chatState?.messages.find(
            message => message.role === 'user' && message.threadID === 'temp',
          )

          if (!lastUserMessage || !lastUserMessage.content) {
            return {
              ok: false,
              result: "We couldn't find the last user message, so we can't redirect, let's build here",
            }
          }

          const contents = encodeURIComponent(lastUserMessage.content)
          window.location.href = `/copilot/spark?initialPrompt=${contents}`

          return {
            ok: true,
            result: `The user is now in the workbench. Our job is done, wish them luck in less than 5 words.`,
          }
        }
        default:
          return {
            ok: false,
            result: `Location is not valid.`,
          }
      }
    } catch (e) {
      const error = `Error: ${e instanceof Error ? e.message : 'Error executing redirect to workbench'}`
      return {
        ok: false,
        result: error,
      }
    }
  }
}
