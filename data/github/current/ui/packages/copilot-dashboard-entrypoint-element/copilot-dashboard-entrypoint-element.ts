import {controller, target} from '@github/catalyst'
import {copilotLocalStorage} from '@github-ui/copilot-chat/utils/copilot-local-storage'
import {sendEvent} from '@github-ui/hydro-analytics'

@controller
export class CopilotDashboardEntrypointElement extends HTMLElement {
  @target declare send_button: HTMLButtonElement
  @target declare copilot_button: HTMLButtonElement
  @target declare textarea: HTMLTextAreaElement
  @target declare footer: HTMLDivElement
  @target declare suggestions: HTMLUListElement
  @target declare disclaimer: HTMLDivElement

  private declare resizeObserver: ResizeObserver

  connectedCallback() {
    this.textarea.value = ''
    this.initializeEventListeners()
    this.adjustTextareaHeight()
    this.toggleFooter()
    this.textarea.value = ''
    this.initializeResizeObserver()
    this.updateSuggestionVisibility()
  }

  disconnectedCallback() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }
  }

  initializeEventListeners() {
    if (this.send_button) {
      this.send_button.addEventListener('click', event => {
        event.preventDefault()
        const newTab = isModifierPressed(event)
        this.submit(undefined, newTab)
        this.textarea.value = ''
      })

      this.send_button.addEventListener('keydown', event => {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (event.key === 'Enter') {
          const newTab = isModifierPressed(event)
          event.preventDefault()
          this.submit(undefined, newTab)
          this.textarea.value = ''
        }
      })
    }

    if (this.copilot_button) {
      this.copilot_button.addEventListener('click', () => {
        sendEvent('dotcom_chat.activate', {
          target: 'DASHBOARD_ENTRYPOINT_COPILOT',
          mode: 'immersive',
        })
      })
    }

    if (this.textarea) {
      this.textarea.addEventListener('input', () => {
        this.adjustTextareaHeight()
        this.toggleFooter()
      })

      this.textarea.addEventListener('keydown', event => {
        // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
        if (event.key === 'Enter') {
          if (isModifierPressed(event)) {
            event.preventDefault()
            this.submit(undefined, true)
            this.textarea.value = ''
          } else if (!event.shiftKey) {
            event.preventDefault()
            this.submit()
          }
        }
      })
    }
  }

  initializeResizeObserver() {
    this.resizeObserver = new ResizeObserver(() => {
      this.adjustTextareaHeight()
      this.toggleFooter()
      this.updateSuggestionVisibility()
    })
    this.resizeObserver.observe(this.suggestions)
  }

  submit(message?: string, newTab: boolean = false) {
    const inputMessage = message || this.textarea.value.trim()
    if (inputMessage) {
      sendEvent('dotcom_chat.activate', {
        target: 'DASHBOARD_ENTRYPOINT_SEND',
        mode: 'immersive',
      })
      copilotLocalStorage.setEntrypointMessage(inputMessage)
      const targetUrl = `/copilot`
      if (newTab) {
        window.open(targetUrl, '_blank', 'noopener,noreferrer')
      } else {
        document.querySelector('.application-main')?.classList.add('appMain--fadeOut')
        setTimeout(() => {
          window.location.href = targetUrl
        }, 200)
      }
    } else {
      this.textarea.focus()
    }
  }

  adjustTextareaHeight() {
    this.textarea.style.height = 'auto'
    this.textarea.style.height = `${this.textarea.scrollHeight}px`
  }

  toggleFooter() {
    if (this.textarea.value.trim()) {
      this.footer.classList.add('copilotPreview__footer--active')
      this.footer.style.height = `${this.disclaimer.scrollHeight}px`
    } else {
      this.footer.classList.remove('copilotPreview__footer--active')
      this.footer.style.height = `${this.suggestions.scrollHeight}px`
    }
  }

  handleSuggestionClick(event: Event) {
    const button = event.currentTarget as HTMLButtonElement
    const raw = button.getAttribute('data-raw')
    const id = button.getAttribute('data-id')
    if (raw) {
      sendEvent('dotcom_chat.activate', {
        target: 'DASHBOARD_ENTRYPOINT_SUGGESTION',
        mode: 'immersive',
        topic: raw,
        suggestionId: id,
      })
      this.submit(raw)
    }
  }

  updateSuggestionVisibility() {
    const suggestionItems = Array.from(this.suggestions.children) as HTMLElement[]
    let totalWidth = 0
    const containerWidth = this.suggestions.clientWidth
    const gap = parseFloat(getComputedStyle(this.suggestions).gap) || 0

    for (const item of suggestionItems) {
      item.style.display = 'block'
      const itemWidth = item.offsetWidth
      totalWidth += itemWidth + gap

      if (totalWidth > containerWidth + gap) {
        item.style.display = 'none'
      } else {
        item.style.display = 'block'
      }
    }
  }
}

function isModifierPressed(event: KeyboardEvent | MouseEvent): boolean {
  // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
  return event.metaKey || event.ctrlKey
}
