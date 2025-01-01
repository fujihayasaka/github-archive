import type {CopilotChatState} from '../copilot-chat-reducer'
import type {ClientSideSkillDefinition} from '../copilot-chat-types'
import type {ClientSkill} from './client-skill'
import styles from './interact-dom.module.css'

interface InteractDOMSkillParams {
  action: 'click' | 'type'
  element: string
  value?: string
}

export class InteractDomSkill implements ClientSkill {
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

  requiresConfirmation(): boolean {
    const functionArguments: InteractDOMSkillParams = JSON.parse(this.rawArguments)
    return functionArguments.action === 'click'
  }

  confirmationMessage(): string {
    const functionArguments = JSON.parse(this.rawArguments)
    let message = ''
    switch (functionArguments.action) {
      case 'click':
        message = `Click on ${functionArguments.element}`
        break
      case 'type':
        message = `Type "${functionArguments.value}" into ${functionArguments.element}`
        break
    }
    return message
  }

  static schema(): ClientSideSkillDefinition {
    return {
      type: 'function',
      function: {
        name: 'interact-dom',
        description:
          'This function gives you the ability to interact with the DOM. Perform an action like clicking on an element, typing into an input, or filling out a form on the current html page. Call this function to fulfill the user request after receiving the current url and tag map of accessible element names to their tags from invoking the read-dom function. For the type action, if there is existing text in the element (passed in the tag map), you should modify that text how the user requests and return the new text contents. Do no just return the new text the user asked you to type unless they are explicitly trying to overwrite the current value. Afterwards, you should send a message letting the user know the actions you performed. If the user makes multiple requests in one message, you should invoke this function multiple times in a single reposnse.',
        parameters: {
          type: 'object',
          required: ['action', 'element'],
          properties: {
            action: {
              type: 'string',
              description:
                'The DOM action to take on an element on the current page. The action property can either be "click" or "type". If it is "type" then the value property should be the string to type into the input element.',
            },
            element: {
              type: 'string',
              description:
                'The accessible name of the element to perform the DOM action on. This must be one of the keys in the tag map returned from read-dom.',
            },
            value: {
              type: 'string',
              description:
                "If the action is 'type', then value is the string to type into the text input element. The text input's value will be set to this, so if the element has an existing value from the tag map passed in, make sure to include that in this paramter.",
            },
          },
        },
      },
    }
  }

  async execute() {
    try {
      const functionArguments: InteractDOMSkillParams = JSON.parse(this.rawArguments)
      const element = this.chatState?.elementMap?.get(functionArguments.element)
      let result = ''
      if (element instanceof HTMLElement) {
        element.classList.add(styles.interactDomSkillHighlight)
        document.addEventListener(
          'click',
          () => {
            element.classList.remove(styles.interactDomSkillHighlight)
          },
          {once: true},
        )
        switch (functionArguments.action) {
          case 'click': {
            element.click()
            result = `${functionArguments.element} was clicked.`
            break
          }
          case 'type': {
            if ('value' in element) {
              element.value = ''
              await typeWriter(element as HTMLInputElement | HTMLTextAreaElement, functionArguments.value || '')
              result = `${functionArguments.value} was typed into ${functionArguments.element}.`
            } else {
              result = `${functionArguments.element} could not be typed into because it was not an element that accepts a value like textarea or input.`
            }
          }
        }
      } else {
        result = `${functionArguments.element} could not be located.`
      }

      return {result, ok: true}
    } catch (e) {
      const error = `Error: ${e instanceof Error ? e.message : `Error executing ${this.name} skill`}`
      return {ok: false, result: error}
    }
  }
}

function typeWriter(element: HTMLInputElement | HTMLTextAreaElement, text: string, i = 0): Promise<void> {
  return new Promise(resolve => {
    function typeCharacter(index: number) {
      if (index < text.length) {
        // // Create a new KeyboardEvent
        const character = text.charAt(index)
        const event = new KeyboardEvent('keydown', {
          key: character,
          code: `Key${character.toUpperCase()}`,
          keyCode: character.charCodeAt(0),
          charCode: character.charCodeAt(0),
          bubbles: true,
        })

        // Dispatch the event to the input element
        element.dispatchEvent(event)

        // Update the input element's value
        element.value += character

        setTimeout(() => typeCharacter(index + 1), 10)
      } else {
        // Create an input event to update the element's value
        const inputEvent = new Event('input', {bubbles: true})
        element.dispatchEvent(inputEvent)
        resolve()
      }
    }
    typeCharacter(i)
  })
}
