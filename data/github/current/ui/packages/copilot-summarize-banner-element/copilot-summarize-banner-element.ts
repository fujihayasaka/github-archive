import {controller, target} from '@github/catalyst'
import {verifiedFetch, verifiedFetchJSON} from '@github-ui/verified-fetch'
import DOMPurify from 'dompurify'
import type {GenerateCopilotSummaryEvent} from './events'
import SummaryCache from './summary-cache'
import type {SummaryFeedbackSentiment} from './types'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {sendEvent} from '@github-ui/hydro-analytics'
import {isTracingEnabled, reportTraceData} from '@github-ui/internal-api-insights'

@controller
export class CopilotSummarizeBannerElement extends HTMLElement {
  @target results: HTMLElement | undefined
  @target skeletonText: HTMLElement | undefined
  @target summarizeButton: HTMLButtonElement | undefined
  @target visibilityText: HTMLElement | undefined
  @target copilotBadge: HTMLElement | undefined
  @target loadingCopilotBadge: HTMLElement | undefined
  @target errorCopilotBadge: HTMLElement | undefined
  @target descriptiveText: HTMLElement | undefined
  @target clipboardCopy: HTMLElement | undefined
  @target feedback: HTMLElement | undefined
  @target newUpdatesIndicator: HTMLElement | undefined
  @target openChatButton: HTMLButtonElement | undefined
  @target positiveFeedbackButton: HTMLButtonElement | undefined
  @target negativeFeedbackButton: HTMLButtonElement | undefined
  @target negativeFeedbackDialog: HTMLDialogElement | undefined
  @target negativeFeedbackForm: HTMLFormElement | undefined
  @target earlyAccessLabel: HTMLElement | undefined
  @target expandSummaryButton: HTMLElement | undefined
  @target minimizeSummaryButton: HTMLElement | undefined
  @target regenerateIconButton: HTMLElement | undefined
  @target container: HTMLElement | undefined
  @target placeholder: HTMLElement | undefined

  summaryGenerated = false
  prompt: string | null = null
  summaryPath: string | null | undefined
  cache: SummaryCache | undefined

  socketEventHandler = (event: Event) => this.#renderNewUpdatesState(event)
  generateSummaryHandler = (event: GenerateCopilotSummaryEvent) => this.#setOptionsAndSummarize(event)
  negativeFeedbackSubmitHandler = (event: SubmitEvent) => this.#submitNegativeFeedback(event)

  connectedCallback() {
    this.addEventListener('socket:message', this.socketEventHandler)
    window.addEventListener('generate-copilot-summary', this.generateSummaryHandler)
    if (this.negativeFeedbackForm) {
      this.negativeFeedbackForm.addEventListener('submit', this.negativeFeedbackSubmitHandler)
    }
    this.summaryPath = this.summarizeButton?.getAttribute('data-path')
    if (this.summaryPath) {
      this.cache = new SummaryCache({contentIdentifier: this.summaryPath})
    }
    this.#restoreCachedSummary()
    this.#hideElement(this.placeholder)
    this.#showElement(this.container)
  }

  disconnectedCallback() {
    window.removeEventListener('generate-copilot-summary', this.generateSummaryHandler)
    if (this.negativeFeedbackForm) {
      this.negativeFeedbackForm.removeEventListener('submit', this.negativeFeedbackSubmitHandler)
    }
    this.removeEventListener('socket:message', this.socketEventHandler)
  }

  async submitPositiveFeedback(event: Event) {
    const button = event.currentTarget as HTMLButtonElement
    const feedbackPath = button.getAttribute('data-path')
    if (typeof feedbackPath !== 'string') return

    const body = {feedback_choices: ['POSITIVE']}
    await verifiedFetchJSON(feedbackPath, {method: 'POST', body})
    this.#afterFeedbackSubmitted('positive')
  }

  #restoreCachedSummary() {
    if (!this.cache) return

    const summary = this.cache.getSummary()
    if (!summary) return
    const summaryMarkdown = this.cache.getSummaryMarkdown()

    this.summaryGenerated = true
    this.#renderSummaryCompleteState(summary, summaryMarkdown || summary)
    const sentiment = this.cache.getSummaryFeedbackSentiment()
    this.#toggleFeedbackButtonsBasedOnSentiment(sentiment)
    this.#setTextContentFromAttribute(this.descriptiveText, 'data-summary-generated-text')

    // Always start from a minimized state
    this.minimizeSummary()
  }

  #toggleFeedbackButtonsBasedOnSentiment(sentiment: SummaryFeedbackSentiment | null) {
    if (!sentiment) return

    if (sentiment === 'positive') {
      this.#hideElement(this.negativeFeedbackButton)
      this.#disableButton(this.positiveFeedbackButton)
    } else {
      this.#hideElement(this.positiveFeedbackButton)
      this.#disableButton(this.negativeFeedbackButton)
    }
  }

  async #submitNegativeFeedback(event: SubmitEvent) {
    event.preventDefault() // don't actually submit the form
    const path = this.negativeFeedbackForm?.action
    if (!path) return

    const body = new FormData(this.negativeFeedbackForm)
    await verifiedFetch(path, {method: 'POST', body})
    this.#afterFeedbackSubmitted('negative')
  }

  #setOptionsAndSummarize(event: GenerateCopilotSummaryEvent) {
    this.prompt = event.payload.prompt
    this.#beginSummarization()
  }

  openChat(_event: Event) {
    const summary = this.cache?.getSummary() ?? ''
    const refName = this.descriptiveText?.getAttribute('data-reference-name-text') ?? 'summary'
    const buttonName = (this.openChatButton?.textContent ?? '').trim()
    const buttonId = this.openChatButton?.id ?? ''

    publishOpenCopilotChat({
      intent: CopilotChatIntents.conversation,
      references: [{type: 'text', name: refName, text: summary}],
      id: buttonId,
      newThread: true,
    })
    sendEvent('inline_summaries.open_chat', {id: buttonId, name: buttonName})
  }

  summarize(_event: Event) {
    this.#beginSummarization()
  }

  async #beginSummarization() {
    this.#hideNewUpdatesState()
    this.#renderLoadingState()
    this.cache?.clear()

    try {
      const summaryOrError = await this.#makeSummarizeRequest()

      if (summaryOrError?.html && summaryOrError?.md) {
        const {html, md} = summaryOrError
        this.#renderSummaryCompleteState(html, md)
        this.summaryGenerated = true
        this.cache?.setSummary({summary: html, summaryMarkdown: md, summaryTimestamp: Date.now()})
      } else {
        this.#renderErrorState()
      }
    } catch (error) {
      let errorMessage: undefined | string
      if (error instanceof Error) {
        errorMessage = error.message
      } else if (typeof error === 'string') {
        errorMessage = error
      }
      this.#renderErrorState(errorMessage)
    }
  }

  async #makeSummarizeRequest() {
    if (typeof this.summaryPath !== 'string') return

    const tracingEnabled = isTracingEnabled()
    const formData = new FormData()
    if (this.prompt) {
      formData.append('prompt', this.prompt)
    }
    if (tracingEnabled) {
      formData.append('_tracing', 'true')
    }
    const response = await verifiedFetch(this.summaryPath, {
      method: 'POST',
      headers: {Accept: 'application/json'},
      body: formData,
    })

    if (response.ok || response.status < 500) {
      const summaryOrError = await response.json()
      if (tracingEnabled) reportTraceData(summaryOrError)
      if (response.ok) return summaryOrError
      throw new Error(summaryOrError?.error)
    }
  }

  #renderNewUpdatesState(event: Event) {
    if (!this.summaryGenerated) return

    const aliveData = (event as CustomEvent)?.detail
    if (!aliveData) return

    this.#showElement(this.newUpdatesIndicator)
    this.#setTextContentFromAttribute(this.descriptiveText, 'data-new-updates-text')
    this.#showElement(this.descriptiveText)
  }

  #hideNewUpdatesState() {
    this.#hideElement(this.newUpdatesIndicator)
  }

  #renderLoadingState() {
    this.#hideElement(this.summarizeButton)
    this.#changeBadgeToLoadingState()
    this.#setTextContentFromAttribute(this.descriptiveText, 'data-loading-text')
    this.#showElement(this.descriptiveText)
    this.#setInnerHtml(this.results, '')
    this.#showElement(this.skeletonText)
    this.#hideElement(this.results)
    this.#resetFeedback()
    this.#hideElement(this.clipboardCopy)
    this.#hideElement(this.regenerateIconButton)
    this.#hideElement(this.openChatButton)
    this.#setValue(this.clipboardCopy, '')
  }

  #renderErrorState(errorMessage?: string) {
    this.#changeBadgeToErrorState()
    this.#hideElement(this.skeletonText)
    if (errorMessage) {
      const domPurifyConfig = {
        FORBID_TAGS: ['style'],
        ALLOW_DATA_ATTR: false,
        ALLOWED_TAGS: ['p'],
      }
      const sanitizedMessage = DOMPurify.sanitize(errorMessage, domPurifyConfig)
      this.#setInnerHtml(this.descriptiveText, sanitizedMessage)
    } else {
      this.#setTextContentFromAttribute(this.descriptiveText, 'data-error-text')
    }
    this.#showElement(this.descriptiveText)
    this.#showTryAgainButton()
    this.#resetFeedback()
    this.#hideElement(this.earlyAccessLabel)
    this.#hideElement(this.clipboardCopy)
    this.#setValue(this.clipboardCopy, '')
  }

  #renderSummaryCompleteState(summaryHtml: string, summaryMd: string) {
    this.#hideElement(this.summarizeButton)
    this.#showElement(this.visibilityText)
    this.#setTextContentFromAttribute(this.descriptiveText, 'data-summary-generated-text')
    this.#setInnerHtml(this.results, summaryHtml)
    this.#showElement(this.results)
    this.#showElement(this.minimizeSummaryButton)
    this.#hideElement(this.skeletonText)
    this.#changeBadgeToDefaultState()
    this.#setValue(this.clipboardCopy, summaryMd)
    this.#showElement(this.clipboardCopy)
    this.#showElement(this.openChatButton)
    this.#showElement(this.regenerateIconButton)
    if (!this.prompt) {
      this.#showElement(this.feedback)
    }
    this.#showElement(this.earlyAccessLabel)
  }

  minimizeSummary() {
    this.#hideElement(this.results)
    this.#hideElement(this.minimizeSummaryButton)
    this.#hideElement(this.clipboardCopy)
    this.#hideElement(this.openChatButton)
    if (!this.prompt) {
      this.#hideElement(this.feedback)
    }
    this.#hideElement(this.regenerateIconButton)
    this.#showElement(this.expandSummaryButton)
  }

  expandSummary() {
    this.#hideElement(this.expandSummaryButton)
    this.#showElement(this.results)
    this.#showElement(this.minimizeSummaryButton)
    this.#showElement(this.clipboardCopy)
    this.#showElement(this.openChatButton)
    if (!this.prompt) {
      this.#showElement(this.feedback)
    }
    this.#showElement(this.regenerateIconButton)
  }

  #showTryAgainButton() {
    this.#setTextContentFromAttribute(this.summarizeButton, 'data-retry-text')
    this.#showElement(this.summarizeButton)
  }

  #afterFeedbackSubmitted(sentiment: SummaryFeedbackSentiment) {
    this.negativeFeedbackDialog?.close()
    this.#toggleFeedbackButtonsBasedOnSentiment(sentiment)
    this.cache?.setSummaryFeedbackSentiment(sentiment)
  }

  #resetFeedback() {
    this.#hideElement(this.feedback)
    this.#showElement(this.positiveFeedbackButton)
    this.#showElement(this.negativeFeedbackButton)
    this.#enableButton(this.positiveFeedbackButton)
    this.#enableButton(this.negativeFeedbackButton)
    this.negativeFeedbackDialog?.close()
  }

  #changeBadgeToLoadingState() {
    this.#hideElement(this.copilotBadge)
    this.#showElement(this.loadingCopilotBadge)
    this.#hideElement(this.errorCopilotBadge)
  }

  #changeBadgeToErrorState() {
    this.#hideElement(this.copilotBadge)
    this.#hideElement(this.loadingCopilotBadge)
    this.#showElement(this.errorCopilotBadge)
  }

  #changeBadgeToDefaultState() {
    this.#hideElement(this.loadingCopilotBadge)
    this.#showElement(this.copilotBadge)
    this.#hideElement(this.errorCopilotBadge)
  }

  #setInnerHtml(element: HTMLElement | undefined, content: string) {
    if (element) element.innerHTML = content
  }

  #setTextContentFromAttribute(element: HTMLElement | undefined, attributeName: string) {
    if (element) {
      const content = element.getAttribute(attributeName)
      element.textContent = content
    }
  }

  #setValue(element: HTMLElement | undefined, value: string) {
    if (element) element.setAttribute('value', value)
  }

  #showElement(element: HTMLElement | undefined) {
    if (element) element.hidden = false
  }

  #hideElement(element: HTMLElement | undefined) {
    if (element) element.hidden = true
  }

  #disableButton(button: HTMLButtonElement | undefined) {
    if (button) button.disabled = true
  }

  #enableButton(button: HTMLButtonElement | undefined) {
    if (button) button.disabled = false
  }
}
