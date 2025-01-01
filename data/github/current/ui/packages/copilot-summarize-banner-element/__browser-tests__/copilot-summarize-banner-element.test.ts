import {assert, fixture, html, setup, suite, test, waitUntil} from '@github-ui/browser-tests'
import {http, HttpResponse} from 'msw'
import {setupWorker} from 'msw/browser'
import {CopilotSummarizeBannerElement} from '../copilot-summarize-banner-element'
import {GenerateCopilotSummaryEvent} from '../events'
import type {GenerateCopilotSummaryPayload} from '../types'
import SummaryCache from '../summary-cache'
import {
  assertDisabled,
  assertEnabled,
  assertHidden,
  assertHiddenButton,
  assertShown,
  assertShownButton,
} from './test-helpers'

// Run these tests via:
// npm run test:watch ui/packages/copilot-summarize-banner-element/__browser-tests__/copilot-summarize-banner-element.test.ts
suite('copilot-summarize-banner-element', () => {
  let container: CopilotSummarizeBannerElement
  const fakeSummarizeEndpointPath = '/some/github/endpoint'
  const fakeFeedbackPath = '/some/feedback/endpoint'
  const initialDescriptiveText = 'summarize this stuff'
  const loadingText = 'loading...'
  const errorText = 'o noes'
  const retryText = 'Dust yourself off and try again'
  const newUpdatesText = 'Something has changed'
  const summaryGeneratedText = 'Summary is generated yo!'
  let summaryCache: SummaryCache | undefined
  const worker = setupWorker()

  setup(async function () {
    container = await fixture(html`
      <copilot-summarize-banner>
        <div data-target="copilot-summarize-banner.placeholder"></div>
        <div data-target="copilot-summarize-banner.container" hidden>
          <span
            data-target="copilot-summarize-banner.descriptiveText"
            data-loading-text="${loadingText}"
            data-error-text="${errorText}"
            data-new-updates-text="${newUpdatesText}"
            data-summary-generated-text="${summaryGeneratedText}"
          >
            ${initialDescriptiveText}
          </span>
          <span data-target="copilot-summarize-banner.newUpdatesIndicator" hidden></span>
          <span data-target="copilot-summarize-banner.earlyAccessLabel" hidden>Super beta</span>
          <div data-target="copilot-summarize-banner.results" hidden></div>
          <div data-target="copilot-summarize-banner.skeletonText" hidden></div>
          <div data-target="copilot-summarize-banner.visibilityText" hidden></div>
          <span data-target="copilot-summarize-banner.copilotBadge"></span>
          <span data-target="copilot-summarize-banner.loadingCopilotBadge" hidden></span>
          <span data-target="copilot-summarize-banner.errorCopilotBadge" hidden></span>
          <button
            data-action="click:copilot-summarize-banner#summarize"
            data-target="copilot-summarize-banner.summarizeButton"
            data-retry-text="${retryText}"
            data-path="${fakeSummarizeEndpointPath}"
          >
            Summarize me
          </button>
          <button
            data-target="copilot-summarize-banner.expandSummaryButton"
            data-action="click:copilot-summarize-banner#expandSummary"
            hidden
          ></button>
          <button
            data-target="copilot-summarize-banner.minimizeSummaryButton"
            data-action="click:copilot-summarize-banner#minimizeSummary"
            hidden
          ></button>
          <clipboard-copy value="" data-target="copilot-summarize-banner.clipboardCopy" hidden>Copy me</clipboard-copy>
          <div data-target="copilot-summarize-banner.feedback" hidden>
            <button
              data-action="click:copilot-summarize-banner#summarize"
              data-target="copilot-summarize-banner.summarizeButton"
              data-retry-text="${retryText}"
              data-path="${fakeSummarizeEndpointPath}"
            >
              Summarize me
            </button>
            <button
              data-target="copilot-summarize-banner.expandSummaryButton"
              data-action="click:copilot-summarize-banner#expandSummary"
              hidden
            ></button>
            <button
              data-target="copilot-summarize-banner.minimizeSummaryButton"
              data-action="click:copilot-summarize-banner#minimizeSummary"
              hidden
            ></button>
            <clipboard-copy value="" data-target="copilot-summarize-banner.clipboardCopy" hidden
              >Copy me</clipboard-copy
            >
            <div data-target="copilot-summarize-banner.feedback" hidden>
              <button
                data-target="copilot-summarize-banner.positiveFeedbackButton"
                data-action="click:copilot-summarize-banner#submitPositiveFeedback"
                data-path="${fakeFeedbackPath}"
              >
                helpful
              </button>
              <dialog data-target="copilot-summarize-banner.negativeFeedbackDialog">
                <button data-target="copilot-summarize-banner.negativeFeedbackButton">not helpful</button>
                <form data-target="copilot-summarize-banner.negativeFeedbackForm" action="${fakeFeedbackPath}">
                  <input id="feedback-choice" type="checkbox" value="UNHELPFUL" name="feedback_choices[]" />
                  <textarea name="feedback_text"></textarea>
                  <button type="submit">Send feedback</button>
                </form>
              </dialog>
              <button
                data-action="click:copilot-summarize-banner#openChat"
                data-target="copilot-summarize-banner.openChatButton"
                hidden
              >
                Follow up in chat
              </button>
              <button
                data-action="click:copilot-summarize-banner#summarize"
                data-target="copilot-summarize-banner.regenerateIconButton"
                hidden
              ></button>
            </div>
          </div>
        </div>
      </copilot-summarize-banner>
    `)
    summaryCache = container.cache
    summaryCache?.clear()
    await worker.start()
  })

  teardown(function () {
    worker.stop()
    worker.resetHandlers()
  })

  test('isConnected', () => {
    assert.isTrue(container.isConnected)
    assert.instanceOf(container, CopilotSummarizeBannerElement)
    assertShown(container.container, 'should have shown banner container after connecting')
    assertHidden(container.placeholder, 'should have hidden placeholder after connecting')
    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.include(
      container.descriptiveText?.textContent,
      initialDescriptiveText,
      'should not have altered starting descriptive text upon connecting component',
    )
    assertHidden(container.results)
    assertHidden(container.visibilityText)
    assert.instanceOf(container.summarizeButton, HTMLButtonElement)
    assert.instanceOf(container.copilotBadge, HTMLElement)
    assertHidden(container.loadingCopilotBadge)
    assertHidden(container.skeletonText)
    assertHidden(container.errorCopilotBadge)
    assertHidden(container.feedback)
    assert.instanceOf(container.positiveFeedbackButton, HTMLButtonElement)
    assert.instanceOf(container.negativeFeedbackDialog, HTMLDialogElement)
    assert.isFalse(container.negativeFeedbackDialog?.open)
    assert.instanceOf(container.negativeFeedbackForm, HTMLFormElement)
    assert.instanceOf(container.negativeFeedbackButton, HTMLButtonElement)
    assertHidden(container.newUpdatesIndicator)
    assertHidden(container.earlyAccessLabel)
    assertHidden(container.clipboardCopy)
    assertHidden(container.openChatButton)
    assert.equal(container.summaryPath, fakeSummarizeEndpointPath)
    assert.instanceOf(container.cache, SummaryCache)
    assertHidden(container.minimizeSummaryButton)
    assertHidden(container.expandSummaryButton)
    assertHiddenButton(container.regenerateIconButton)
  })

  test('clicking Summarize button shows summary', async () => {
    // eslint-disable-next-line github/unescaped-html-literal
    const fakeSummary = '<p>Hello world</p>'
    const fakeSummaryMd = '*Hello world*'
    let requestCount = 0
    let requestBody: string | undefined
    worker.use(
      http.post(fakeSummarizeEndpointPath, async ({request}) => {
        requestBody = await request.text()
        requestCount++
        return HttpResponse.json({html: fakeSummary, md: fakeSummaryMd})
      }),
    )

    container.summarizeButton?.click()

    assertHiddenButton(container.summarizeButton, 'should have hidden summarize button')
    assertShown(container.loadingCopilotBadge, 'should have shown loading badge')
    assertShown(container.skeletonText, 'should have shown skeleton text')

    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      loadingText,
      'should have set descriptive text to data-loading-text',
    )

    await waitUntil(() => requestCount === 1, 'expected summarize request to be made')

    assert.include(requestBody, 'FormBoundary')
    assert.notInclude(requestBody, 'prompt', 'should not have sent a prompt parameter in summarize request')
    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'should have set descriptive text to summary generated',
    )
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
    assertShown(container.results, 'should have shown results')
    assertShown(container.visibilityText, 'should have shown visibility text')
    assert.equal(container.results?.innerHTML, fakeSummary, 'should have rendered summary HTML')
    assertShown(container.copilotBadge, 'should have shown Copilot badge')
    assertHidden(container.loadingCopilotBadge, 'should have hidden loading Copilot badge')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assertShown(container.feedback, 'should have shown feedback buttons')
    assertShown(container.clipboardCopy, 'should have shown copy button')
    assertShown(container.openChatButton, 'should have shown open chat button')
    assertShown(container.regenerateIconButton, 'should have shown regenerate icon button')
    assert.equal(
      container.clipboardCopy?.getAttribute('value'),
      fakeSummaryMd,
      'should have set text to be copied to text value of summary, not HTML',
    )
    assert.equal(summaryCache?.getSummary(), fakeSummary, 'should have cached summary response')
    assertShown(container.minimizeSummaryButton, 'should have shown minimize summary toggle')

    worker.stop()
    worker.resetHandlers()
  })

  test('listens for generate-copilot-summary event', async () => {
    let requestBody: unknown
    worker.use(
      http.post(fakeSummarizeEndpointPath, async ({request}) => {
        const formData = await request.formData()
        requestBody = Object.fromEntries(formData)
        return HttpResponse.json({html: 'some summary', md: 'some summary'})
      }),
    )
    const eventPayload: GenerateCopilotSummaryPayload = {prompt: 'my great new prompt'}

    window.dispatchEvent(new GenerateCopilotSummaryEvent(eventPayload))

    await waitUntil(() => requestBody !== undefined, 'expected POST request to be made')

    assert.equal(JSON.stringify(eventPayload), JSON.stringify(requestBody))
    assertHidden(container.feedback, 'should hide feedback buttons for custom prompt')
  })

  test('shows error state on error from api', async () => {
    let requestCount = 0
    const errorMessageFromServer = "This discussion can't be summarized right now. Please try again later."
    worker.use(
      http.post(fakeSummarizeEndpointPath, () => {
        requestCount++
        return HttpResponse.json({error: errorMessageFromServer}, {status: 422})
      }),
    )

    container.summarizeButton?.click()

    assertHiddenButton(container.summarizeButton, 'expected summarize button to be hidden')
    assertShown(container.loadingCopilotBadge, 'expected loading badge to be shown')
    assertShown(container.skeletonText, 'expected skeleton text to be shown')

    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      loadingText,
      'should have set descriptive text to data-loading-text attribute',
    )

    await waitUntil(() => requestCount === 1, 'expected POST request to be made')

    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      errorMessageFromServer,
      'should have set descriptive text to error message returned by server',
    )
    assertShown(container.descriptiveText, 'should have shown descriptive text with error')
    assertHidden(container.earlyAccessLabel, 'should have kept early access indicator hidden')
    assertShown(container.errorCopilotBadge, 'expected error badge to be shown')
    assertShownButton(container.summarizeButton, 'expected summarize button to be shown')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assert.equal(
      container.summarizeButton?.textContent,
      retryText,
      'should have set summarize button text to data-retry-text',
    )
    assertHidden(container.feedback, 'should have hidden feedback buttons')
    assertHidden(container.clipboardCopy, 'should have hidden copy button')
    assertHidden(container.openChatButton, 'should have hidden open chat button')
    assertHidden(container.regenerateIconButton, 'should have hidden regenerate icon button')
    assert.isNull(summaryCache?.getSummary(), 'should not have cached error response as summary')
    assertHidden(container.minimizeSummaryButton, 'should have hidden minimize summary button')

    worker.stop()
    worker.resetHandlers()
  })

  test('shows error state when the api returns a 500', async () => {
    let requestCount = 0

    worker.use(
      http.post(fakeSummarizeEndpointPath, async () => {
        requestCount++
        return new HttpResponse('Internal server error', {status: 500})
      }),
    )

    container.summarizeButton?.click()

    assertHiddenButton(container.summarizeButton, 'expected summarize button to be hidden')
    assertShown(container.loadingCopilotBadge, 'expected loading badge to be shown')
    assertShown(container.skeletonText, 'expected skeleton text to be shown')

    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      loadingText,
      'should have set descriptive text to data-loading-text attribute',
    )
    assertShown(container.descriptiveText, 'should have shown descriptive text with loading message')

    await waitUntil(() => requestCount === 1, 'expected POST request to be made')

    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      errorText,
      'should have set descriptive text to data-error-text',
    )
    assertShown(container.descriptiveText, 'should have shown descriptive text with error')

    assertHidden(container.earlyAccessLabel, 'should have kept early access indicator hidden')
    assertShown(container.errorCopilotBadge, 'expected error badge to be shown')
    assertShownButton(container.summarizeButton, 'expected summarize button to be shown')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assert.equal(
      container.summarizeButton?.textContent,
      retryText,
      'should have set summarize button text to data-retry-text',
    )
    assertHidden(container.feedback, 'should have hidden feedback buttons')
    assertHidden(container.clipboardCopy, 'should have hidden copy button')
    assertHidden(container.openChatButton, 'should have hidden open chat button')
    assertHidden(container.regenerateIconButton, 'should have hidden regenerate icon button')
    assert.isNull(summaryCache?.getSummary(), 'should not have cached error response as summary')
    assertHidden(container.minimizeSummaryButton, 'should have hidden minimize summary button')

    worker.stop()
    worker.resetHandlers()
  })

  test('can minimize and expand generated summary', async () => {
    let summarizeRequestCount = 0
    worker.use(
      http.post(fakeSummarizeEndpointPath, () => {
        summarizeRequestCount++
        return HttpResponse.json({html: 'some summary', md: 'some summary'})
      }),
    )

    // Request summary
    container.summarizeButton?.click()
    await waitUntil(() => summarizeRequestCount === 1, 'expected summarization request to be made')
    assertShown(container.results, 'should have shown generated summary')
    assertShown(container.minimizeSummaryButton, 'should have shown minimize button')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'should have set descriptive text to summary generated',
    )

    // minimize the banner
    container.minimizeSummaryButton?.click()
    assertHidden(container.results, 'should have hidden results after minimizing')
    assertHidden(container.clipboardCopy, 'should have hidden clipboard copy button after minimizing')
    assertHidden(container.openChatButton, 'should have hidden open chat button after minimizing')
    assertHidden(container.minimizeSummaryButton, 'should have hidden minimize button after minimizing')
    assertHidden(container.feedback, 'should have feedback buttons after minimizing')
    assertShown(container.expandSummaryButton, 'should have shown expand button after minimizing')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'should show descriptive text even when minimized',
    )

    // expand the banner
    container.expandSummaryButton?.click()
    assertShown(container.results, 'should have shown results after expanding')
    assertShown(container.clipboardCopy, 'should have shown clipboard copy button after expanding')
    assertShown(container.openChatButton, 'should have shown open chat button after expanding')
    assertShown(container.minimizeSummaryButton, 'should have shown minimize button after expanding')
    assertShown(container.feedback, 'should have shown feedback buttons after expanding')
    assertHidden(container.expandSummaryButton, 'should have hidden expand button after expanding')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'should show the descriptive text when expanded',
    )
  })

  test('submits positive feedback when button is clicked after summarizing', async () => {
    let summarizeRequestCount = 0
    let feedbackRequestCount = 0
    let feedbackRequestBody: unknown
    worker.use(
      http.post(fakeSummarizeEndpointPath, () => {
        summarizeRequestCount++
        return HttpResponse.json({html: 'some summary', md: 'some summary'})
      }),
      http.post(fakeFeedbackPath, async ({request}) => {
        feedbackRequestBody = await request.json()
        feedbackRequestCount++
        return new HttpResponse('', {status: 201})
      }),
    )

    // Request summary
    container.summarizeButton?.click()
    await waitUntil(() => summarizeRequestCount === 1, 'expected summarization request to be made')
    assertShown(container.feedback, 'should have shown feedback buttons')
    assertShown(container.clipboardCopy, 'should have shown copy button')

    // Submit positive feedback
    container.positiveFeedbackButton?.click()
    await waitUntil(() => feedbackRequestCount === 1, 'expected feedback request to be made')
    const expectedFeedbackRequestBody = {feedback_choices: ['POSITIVE']}
    assert.equal(JSON.stringify(feedbackRequestBody), JSON.stringify(expectedFeedbackRequestBody))
    assertDisabled(container.positiveFeedbackButton, 'should have disabled positive feedback button')
    assertShown(container.earlyAccessLabel, 'should have kept early access indicator visible')
    assertHiddenButton(container.negativeFeedbackButton, 'should have hidden negative feedback button')
    assertShown(container.clipboardCopy, 'should have kept copy button visible')
    assertShown(container.regenerateIconButton, 'should have shown regenerate icon button')
    assert.equal(summaryCache?.getSummaryFeedbackSentiment(), 'positive', 'should have cached feedback type')
  })

  test('submits negative feedback when form is submitted after summarizing', async () => {
    let summarizeRequestCount = 0
    let feedbackRequestCount = 0
    let feedbackRequestBody = ''
    const customFeedbackText = 'some extra commentary'
    worker.use(
      http.post(fakeSummarizeEndpointPath, () => {
        summarizeRequestCount++
        return HttpResponse.json({html: 'some summary', md: 'some summary'})
      }),
      http.post(fakeFeedbackPath, async ({request}) => {
        feedbackRequestBody = await request.text()
        feedbackRequestCount++
        return new HttpResponse('', {status: 201})
      }),
    )

    container.summarizeButton?.click()

    await waitUntil(() => summarizeRequestCount === 1, 'expected summarization request to be made')

    assertShown(container.feedback, 'should have shown feedback buttons')
    assertShown(container.clipboardCopy, 'should have shown copy button')

    const feedbackChoiceCheckbox = container.negativeFeedbackForm?.querySelector('#feedback-choice') as HTMLInputElement
    feedbackChoiceCheckbox.checked = true

    const feedbackTextarea = container.negativeFeedbackForm?.querySelector(
      'textarea[name=feedback_text]',
    ) as HTMLTextAreaElement
    feedbackTextarea.value = customFeedbackText

    const negativeFeedbackSubmitButton = container.negativeFeedbackForm?.querySelector(
      'button[type=submit]',
    ) as HTMLButtonElement
    negativeFeedbackSubmitButton.click()

    await waitUntil(() => feedbackRequestCount === 1, 'expected feedback request to be made')

    assert.include(feedbackRequestBody, 'Content-Disposition: form-data; name="feedback_choices[]"')
    assert.include(feedbackRequestBody, 'Content-Disposition: form-data; name="feedback_text"')
    assert.include(feedbackRequestBody, feedbackChoiceCheckbox.value)
    assert.include(feedbackRequestBody, customFeedbackText)
    assertShown(container.earlyAccessLabel, 'should have kept early access indicator visible')
    assertShown(container.clipboardCopy, 'should have kept copy button visible')
    assertShown(container.regenerateIconButton, 'should have shown regenerate icon button')
    assert.equal(summaryCache?.getSummaryFeedbackSentiment(), 'negative', 'should have cached feedback type')
  })

  test('Can regenerate summary using the regenerate summary icon button', async () => {
    let requestCount = 0
    worker.use(
      http.post(fakeSummarizeEndpointPath, () => {
        requestCount++
        // eslint-disable-next-line github/unescaped-html-literal
        return HttpResponse.json({html: '<p>Hello world</p>', md: '*Hello world*'})
      }),
    )

    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(container.descriptiveText?.textContent?.trim(), initialDescriptiveText)

    // Request summary
    container.summarizeButton?.click()
    await waitUntil(() => requestCount === 1, 'expected summarize request to be made')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'Should show summary generated text after generating summary',
    )
    assertShown(container.feedback, 'should have shown feedback buttons')
    assertShownButton(container.positiveFeedbackButton, 'should have shown positive feedback button')
    assertShownButton(container.negativeFeedbackButton, 'should have shown negative feedback button')
    assertEnabled(container.positiveFeedbackButton, 'should have enabled positive feedback button')
    assertEnabled(container.negativeFeedbackButton, 'should have enabled negative feedback button')
    assertShown(container.clipboardCopy, 'should have shown copy button')
    assertShown(container.regenerateIconButton, 'should have shown regenerate icon button')
    assert.equal(
      container.clipboardCopy?.getAttribute('value'),
      '*Hello world*',
      'should have set text to be copied to text value of summary, not HTML',
    )

    // Regenerate summary
    container.regenerateIconButton?.click()
    assertHidden(container.clipboardCopy, 'should have hidden copy button while regenerating')
    assertHidden(container.regenerateIconButton, 'should have hidden regenerate icon button while regenerating')
    assertShown(container.descriptiveText, 'should have shown descriptive text with loading message')
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator when loading')

    await waitUntil(() => requestCount === 2, 'expected POST request to be made')
    assert.instanceOf(container.descriptiveText, HTMLElement)
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'Should show summary generated text after generating summary',
    )
    assertHidden(container.newUpdatesIndicator, 'should have hidden new updates indicator')
    assertShownButton(container.positiveFeedbackButton, 'should have shown positive feedback button')
    assertShownButton(container.negativeFeedbackButton, 'should have shown negative feedback button')
    assertShown(container.earlyAccessLabel, 'should have kept early access indicator visible')
    assertEnabled(container.positiveFeedbackButton, 'should have enabled positive feedback button')
    assertEnabled(container.negativeFeedbackButton, 'should have enabled negative feedback button')
    assertShown(container.clipboardCopy, 'should have shown copy button')
    assertShown(container.regenerateIconButton, 'should have kept regenerate icon button visible')
  })

  test('Shows minimized cached summary initially when it exists', () => {
    // eslint-disable-next-line github/unescaped-html-literal
    const fakeCachedSummary = "<p>You won't believe the quality of this summary, oh boy.</p>"
    const fakeCachedSummaryMd = "*You won't believe the quality of this summary, oh boy.*"

    summaryCache?.setSummary({
      summary: fakeCachedSummary,
      summaryMarkdown: fakeCachedSummaryMd,
      summaryTimestamp: Date.now(),
    })

    assertShown(container, 'should have shown banner after connecting')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'Should show descriptive summary generated text when cached summary exists',
    )
    assertHiddenButton(container.summarizeButton, 'should have hidden summarize button')
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
    assertHidden(container.results, 'should not have shown results')
    assertShown(container.visibilityText, 'should have shown visibility text')
    assert.equal(container.results?.innerHTML, fakeCachedSummary, 'should have rendered cached summary HTML')
    assertShown(container.copilotBadge, 'should have shown Copilot badge')
    assertHidden(container.loadingCopilotBadge, 'should have hidden loading Copilot badge')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assertHidden(container.feedback, 'should not have shown feedback buttons')
    assertShownButton(container.positiveFeedbackButton, 'should have shown positive feedback button')
    assertShownButton(container.negativeFeedbackButton, 'should have shown negative feedback button')
    assertEnabled(container.positiveFeedbackButton, 'should have enabled positive feedback button')
    assertEnabled(container.negativeFeedbackButton, 'should have enabled negative feedback button')
    assertHidden(container.clipboardCopy, 'should not have shown copy button')
    assertHidden(container.regenerateIconButton, 'should not have shown regenerate icon button')
    assert.equal(
      container.clipboardCopy?.getAttribute('value'),
      fakeCachedSummaryMd,
      'should have set text to be copied to text value of cached summary, not HTML',
    )
    assertShown(container.expandSummaryButton, 'should have shown expand summary button')
  })

  test('Clears cached summary when Regenerate is clicked', () => {
    // eslint-disable-next-line github/unescaped-html-literal
    const fakeCachedSummary = "<p>You won't believe the quality of this summary, oh boy.</p>"
    const fakeCachedSummaryMd = "*You won't believe the quality of this summary, oh boy.*"
    summaryCache?.setSummary({
      summary: fakeCachedSummary,
      summaryMarkdown: fakeCachedSummaryMd,
      summaryTimestamp: Date.now(),
    })

    container.regenerateIconButton?.click()

    assert.isNull(summaryCache?.getSummary(), 'should have cleared cached summary response')
  })

  test('Shows cached summary and feedback vote initially when they exist', () => {
    // eslint-disable-next-line github/unescaped-html-literal
    const fakeCachedSummary = '<p>This right here is a nice summary.</p>'
    const fakeCachedSummaryMd = '*This right here is a nice summary.*'
    summaryCache?.setSummary({
      summary: fakeCachedSummary,
      summaryMarkdown: fakeCachedSummaryMd,
      summaryTimestamp: Date.now(),
    })
    const fakeCachedFeedbackVote = 'positive'
    summaryCache?.setSummaryFeedbackSentiment(fakeCachedFeedbackVote)

    assertShown(container, 'should have shown banner after connecting')
    assertHidden(container.newUpdatesIndicator, 'should have hidden new updates indicator')
    assertHiddenButton(container.summarizeButton, 'should have hidden summarize button')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'Should show descriptive summary generated text when cached summary exists',
    )
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
    assertHidden(container.results, 'should not have shown results')
    assertShown(container.visibilityText, 'should have shown visibility text')
    assert.equal(container.results?.innerHTML, fakeCachedSummary, 'should have rendered cached summary HTML')
    assertShown(container.copilotBadge, 'should have shown Copilot badge')
    assertHidden(container.loadingCopilotBadge, 'should have hidden loading Copilot badge')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assertHidden(container.feedback, 'should not have shown feedback buttons')
    assertShownButton(container.positiveFeedbackButton, 'should have shown positive feedback button')
    assertHiddenButton(container.negativeFeedbackButton, 'should have hidden negative feedback button')
    assertDisabled(container.positiveFeedbackButton, 'should have disabled positive feedback button')
    assertEnabled(container.negativeFeedbackButton, 'should have enabled negative feedback button')
    assert.equal(
      container.clipboardCopy?.getAttribute('value'),
      fakeCachedSummaryMd,
      'should have set text to be copied to text value of cached summary, not HTML',
    )
  })

  test('Shows new update indicator when updates come in when a minimized cached summary is shown', () => {
    // eslint-disable-next-line github/unescaped-html-literal
    const fakeCachedSummary = '<p>I am enjoying this matcha.</p>'
    const fakeCachedSummaryMd = '*I am enjoying this matcha.*'
    summaryCache?.setSummary({
      summary: fakeCachedSummary,
      summaryMarkdown: fakeCachedSummaryMd,
      summaryTimestamp: Date.now(),
    })

    // Start out with cached summary shown
    assertShown(container, 'should have shown banner after connecting')
    assertHiddenButton(container.summarizeButton, 'should have hidden summarize button')
    assertHidden(container.newUpdatesIndicator, 'should have hidden new updates indicator')
    assert.equal(
      container.descriptiveText?.textContent,
      summaryGeneratedText,
      'Should show descriptive summary generated text when cached summary exists',
    )
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
    assertHidden(container.results, 'should not have shown results')
    assertShown(container.visibilityText, 'should have shown visibility text')
    assert.equal(container.results?.innerHTML, fakeCachedSummary, 'should have rendered cached summary HTML')
    assertShown(container.copilotBadge, 'should have shown Copilot badge')
    assertHidden(container.loadingCopilotBadge, 'should have hidden loading Copilot badge')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assertHidden(container.feedback, 'should not have shown feedback buttons')
    assertShownButton(container.positiveFeedbackButton, 'should have shown positive feedback button')
    assertShownButton(container.negativeFeedbackButton, 'should have shown negative feedback button')
    assertEnabled(container.positiveFeedbackButton, 'should have enabled positive feedback button')
    assertEnabled(container.negativeFeedbackButton, 'should have enabled negative feedback button')
    assertHidden(container.clipboardCopy, 'should not have shown copy button')
    assertHidden(container.regenerateIconButton, 'should not have shown regenerate icon button')
    assert.equal(
      container.clipboardCopy?.getAttribute('value'),
      fakeCachedSummaryMd,
      'should have set text to be copied to text value of cached summary, not HTML',
    )

    // Simulate update to discussion
    container.dispatchEvent(new CustomEvent('socket:message', {detail: {name: 'Discussion:#1', data: {gid: 'foobar'}}}))
    assert.equal(container.descriptiveText?.textContent?.trim(), newUpdatesText)
    assertShown(container.newUpdatesIndicator, 'should have shown new updates indicator')
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
  })

  test('Shows new update indicator when updates come in when an expanded cached summary is shown', () => {
    // eslint-disable-next-line github/unescaped-html-literal
    const fakeCachedSummary = '<p>I am enjoying this matcha.</p>'
    const fakeCachedSummaryMd = '*I am enjoying this matcha.*'
    summaryCache?.setSummary({
      summary: fakeCachedSummary,
      summaryMarkdown: fakeCachedSummaryMd,
      summaryTimestamp: Date.now(),
    })

    // expand the banner
    container.expandSummaryButton?.click()

    // Start out with cached summary shown
    assertShown(container, 'should have shown banner after connecting')
    assertHiddenButton(container.summarizeButton, 'should have hidden summarize button')
    assertHidden(container.newUpdatesIndicator, 'should have hidden new updates indicator')
    assertShown(container.descriptiveText, 'should have shown descriptive text after showing cached summary')
    assert.equal(container.descriptiveText?.textContent, summaryGeneratedText)
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
    assertShown(container.results, 'should have shown results')
    assertShown(container.visibilityText, 'should have shown visibility text')
    assert.equal(container.results?.innerHTML, fakeCachedSummary, 'should have rendered cached summary HTML')
    assertShown(container.copilotBadge, 'should have shown Copilot badge')
    assertHidden(container.loadingCopilotBadge, 'should have hidden loading Copilot badge')
    assertHidden(container.skeletonText, 'should have hidden skeleton text')
    assertShown(container.feedback, 'should have shown feedback buttons')
    assertShownButton(container.positiveFeedbackButton, 'should have shown positive feedback button')
    assertShownButton(container.negativeFeedbackButton, 'should have shown negative feedback button')
    assertEnabled(container.positiveFeedbackButton, 'should have enabled positive feedback button')
    assertEnabled(container.negativeFeedbackButton, 'should have enabled negative feedback button')
    assertShown(container.clipboardCopy, 'should have shown copy button')
    assertShown(container.regenerateIconButton, 'should have shown regenerate icon button')
    assert.equal(
      container.clipboardCopy?.getAttribute('value'),
      fakeCachedSummaryMd,
      'should have set text to be copied to text value of cached summary, not HTML',
    )

    // Simulate update to discussion
    container.dispatchEvent(new CustomEvent('socket:message', {detail: {name: 'Discussion:#1', data: {gid: 'foobar'}}}))
    assert.equal(container.descriptiveText?.textContent?.trim(), newUpdatesText)
    assertShown(container.newUpdatesIndicator, 'should have shown new updates indicator')
    assertShown(container.earlyAccessLabel, 'should have shown early access indicator')
  })
})
