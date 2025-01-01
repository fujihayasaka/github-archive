import type {Message} from './api'
import type {PromptCfg} from './config'

export async function expandPrompt(p: PromptCfg): Promise<Message[]> {
  switch (true) {
    case 'prompt' in p && typeof p.prompt === 'string':
      return [
        {
          timestamp: new Date(),
          role: 'user',
          message: p.prompt,
        },
      ]

    case 'messages' in p && Array.isArray(p.messages):
      return p.messages

    default:
      throw new Error('Invalid prompt configuration')
  }
}
