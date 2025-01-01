import {getAccessibleName} from 'accname'

import type {CopilotChatState, Dispatcher} from '../copilot-chat-reducer'
import type {ClientSideSkillDefinition} from '../copilot-chat-types'
import type {ClientSkill} from './client-skill'

interface TagMap {
  [key: string]: {tag: string; value: string | null}
}

export class ReadDomSkill implements ClientSkill {
  id: string
  name: string
  rawArguments: string
  dispatch: Dispatcher | undefined

  constructor(id: string, name: string, rawArguments: string, chatState?: CopilotChatState, dispatch?: Dispatcher) {
    this.id = id
    this.name = name
    this.rawArguments = rawArguments
    this.dispatch = dispatch
  }

  requiresConfirmation(): boolean {
    return false
  }

  confirmationMessage(): string {
    return 'Read the DOM for the current page'
  }

  static schema(): ClientSideSkillDefinition {
    return {
      type: 'function',
      function: {
        name: 'read-dom',
        description:
          'Allows you to interact with the DOM to perform actions like filling out forms, submitting forms, clicking on buttons, and typing into inputs on the current web page. This function requests a list of all interactable elements on the current html page, keyed by their accessible name. If the user makes a request to interact with elements on the current web page, but has not provided any DOM elements in clientToolResults, call this function. After the results are returned, call interact-dom to actually perform the desired interactions. If the user asks a question about the DOM, you can call this to read its state, but do not follow up with an interact-dom function call in that case. Finally, let the user know what actions you performed',
        parameters: {
          type: 'object',
          properties: {},
        },
      },
    }
  }

  execute() {
    try {
      const tagMap: TagMap = {}
      const elementMap = new Map<string, Element>()
      const interactableElements = document.querySelectorAll(
        'input, select, textarea, button, [role="button"], a, [tabindex]',
      )
      for (const element of interactableElements) {
        const name = getAccessibleName(element)
        elementMap.set(name, element)
        const tag = element.tagName
        const value =
          element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement ? element.value : null
        tagMap[name] = {tag, value}
      }
      this.dispatch?.({
        type: 'READ_DOM_SKILL_INVOKED',
        elementMap,
      })
      const result = JSON.stringify({tagMap, url: window.location.href})

      return {result, ok: true}
    } catch (e) {
      const error = `Error: ${e instanceof Error ? e.message : `Error executing ${this.name} skill`}`
      return {ok: false, result: error}
    }
  }
}
