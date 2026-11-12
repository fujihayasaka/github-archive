import { controller, target } from '@github/catalyst'

interface ErrorHash {
  [key: string]: string
}

@controller
export class CopilotChatElement extends HTMLElement {
  @target sendButton: HTMLButtonElement
  @target requestMessageInput: HTMLInputElement
  @target responseContainer: HTMLElement

  csrfParam: string

  private keydownHandler?: (event: KeyboardEvent) => Promise<void>

  constructor() {
    super()
  }

  connectedCallback() {
    this.csrfParam = (
      document.querySelector('meta[name=csrf-token]') as HTMLMetaElement
    )?.content

    // Store the handler so we can remove it later
    this.keydownHandler = async (event: KeyboardEvent) => {
      if (event.key === 'Enter' && this.requestMessageInput.matches(':focus')) {
        await this.fetchResponse()
      }
    }

    this.addEventListener('keydown', this.keydownHandler)
  }

  disconnectedCallback() {
    if (this.keydownHandler) {
      this.removeEventListener('keydown', this.keydownHandler)
      this.keydownHandler = undefined
    }
  }

  async fetchResponse() {
    const message = this.requestMessageInput.value.trim()

    // Don't send empty messages
    if (!message) return

    this.displayUserMessage(message)
    this.clearInput()
    this.toggleSendButton(true)

    try {
      const response = await this.sendMessageToServer(message)

      if (response.ok) {
        const data = await response.json()
        this.displayBotResponse(data.message)
      } else {
        const errorData: ErrorHash = await response.json()
        this.handleError(errorData.error)
      }
    } catch (error) {
      this.handleError('Network error occurred')
    } finally {
      this.toggleSendButton(false)
    }
  }

  private displayUserMessage(message: string) {
    const messageElement = document.createElement('p')
    messageElement.textContent = message
    messageElement.classList.add('user-message')
    this.responseContainer.appendChild(messageElement)
    this.scrollToBottom()
  }

  private displayBotResponse(message: string) {
    const responseElement = document.createElement('div')
    responseElement.classList.add('bot-response')

    // Safely parse and append HTML content
    this.appendHTMLContent(responseElement, message)

    this.responseContainer.appendChild(responseElement)
    this.scrollToBottom()
  }

  // NOTE: I noticed some slowness when rendering large messages.
  // We need to optimize this, possibly by using DOMPurify.
  private appendHTMLContent(container: HTMLElement, htmlString: string) {
    // Use DOMParser for safer HTML parsing
    const parser = new DOMParser()
    const doc = parser.parseFromString(htmlString, 'text/html')

    // Append all body children to the container
    // eslint-disable-next-line github/array-foreach
    Array.from(doc.body.childNodes).forEach((node) => {
      container.appendChild(node.cloneNode(true))
    })
  }

  private async sendMessageToServer(message: string): Promise<Response> {
    return fetch('/chat', {
      method: 'POST',
      body: JSON.stringify({ message }),
      headers: {
        'x-csrf-token': this.csrfParam,
        'Content-Type': 'application/json',
      },
    })
  }

  private toggleSendButton(disabled: boolean) {
    this.sendButton.disabled = disabled
  }

  private clearInput() {
    this.requestMessageInput.value = ''
  }

  private handleError(errorMsg: string) {
    const errorMessage = document.createElement('p')
    errorMessage.textContent = errorMsg
    errorMessage.classList.add('error-message')

    this.responseContainer.appendChild(errorMessage)
    this.scrollToBottom()
  }

  private scrollToBottom() {
    this.responseContainer.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }
}
