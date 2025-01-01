import {assert, fixture, html, setup, suite, test, elementUpdated} from '@github-ui/browser-tests'
import {CopilotTextCompletionElement} from '../copilot-text-completion-element'
import type {GhostManagerV2} from '../ghost-manager-v2'
import type {Context} from '../context'
import type {IncludeFragmentElement} from '@github/include-fragment-element'
import {restore, spy, stub} from 'sinon'
import {featureFlag} from '@github-ui/feature-flags'

suite('copilot-text-completion-element', () => {
  let container: HTMLDivElement
  let component: CopilotTextCompletionElement
  let source: HTMLTextAreaElement
  let ghost: HTMLPreElement
  let rulerTextArea: HTMLTextAreaElement
  let manager: GhostManagerV2
  let context: Context
  let accessibleDialog: HTMLDialogElement
  let accessibleDialogAccept: HTMLButtonElement
  let accessibleDialogReject: HTMLButtonElement

  setup(async function () {
    const isFeatureEnabledStub = stub(featureFlag, 'isFeatureEnabled')
    isFeatureEnabledStub.withArgs('GHOST_PILOT_VNEXT').returns(true)
    container = await fixture(
      html`<div>
        <textarea id="source"></textarea>
        <copilot-text-completion id="component" data-source-element-id="source">
          <div class="copilot-octicon"></div>
          <dialog id="dialog" data-target="copilot-text-completion.accessibleDialog"></dialog>
          <button id="accept_button" data-target="copilot-text-completion.accessibleDialogAccept"></button>
          <button id="reject_button" data-target="copilot-text-completion.accessibleDialogReject"></button>
        </copilot-text-completion>
        <include-fragment id="frag-it" data-ghost-pilot-context data-src="bunk/foo%2Fbar"></include-fragment>
      </div>`,
    )

    component = container.querySelector('#component') as CopilotTextCompletionElement
    source = container.querySelector('#source') as HTMLTextAreaElement
    source.focus()
    ghost = container.querySelector('#source_ghost') as HTMLPreElement
    rulerTextArea = container.querySelector('#source_ghost_ruler') as HTMLTextAreaElement
    accessibleDialog = container.querySelector('#dialog') as HTMLDialogElement
    accessibleDialogAccept = container.querySelector('#accept_button') as HTMLButtonElement
    accessibleDialogReject = container.querySelector('#reject_button') as HTMLButtonElement
    manager = component.manager as GhostManagerV2
    context = component.context as Context
  })

  teardown(() => {
    restore()
  })

  const mockCompletion = (
    text: string | undefined,
    tokens: Array<{
      text: string
      tokens: [string]
      token_logprobs: [number]
      top_logprobs: Array<{[key: string]: number}>
    }> = [],
  ) => {
    component.api.complete = async () => {
      component.api.lastTokens = tokens
      return text
    }
  }

  test('isConnected', () => {
    assert.isTrue(component.isConnected)
    assert.instanceOf(component, CopilotTextCompletionElement)
    assert.equal(source, component.source)

    assert.isNotNull(source)
    assert.isNotNull(ghost)
    assert.isNotNull(rulerTextArea)
    assert.isNotNull(manager)
    assert.isNotNull(manager.ruler)

    assert.equal(manager.source, source)
  })

  describe('initializeAsyncContexts', () => {
    test('flops data-src to the real source', () => {
      const fragment = container.querySelector('#frag-it') as IncludeFragmentElement
      assert.isUndefined(fragment.src)
      assert.equal(fragment.getAttribute('data-src'), 'bunk/foo%2Fbar')

      component.initializeAsyncContexts()
      assert.equal(fragment.src, `${window.location.origin}/bunk/foo%2Fbar`)
      assert.isNull(fragment.getAttribute('data-src'))
    })
  })

  // Events that just cancel so group them
  describe('moving away', () => {
    for (const eventName of ['blur', 'mousedown']) {
      test(`cancels on ${eventName}`, async () => {
        source.value = 'original'
        ghost.textContent = 'suggested'
        manager.currentSuggestion = 'suggested'

        const event = new Event(eventName)
        source.dispatchEvent(event)

        assert.equal(source.value, 'original')
        await elementUpdated(ghost)
        assert.equal(ghost.textContent, '')
        assert.equal(manager.currentSuggestion, null)
      })
    }
  })

  describe('keydown', () => {
    test('accepts on tab', () => {
      source.value = ''
      ghost.textContent = 'suggested'
      manager.currentSuggestion = 'suggested'

      const event = new KeyboardEvent('keydown', {key: 'Tab'})
      source.dispatchEvent(event)

      assert.equal(source.value, 'suggested')
      assert.equal(ghost.textContent, '')
      assert.equal(manager.currentSuggestion, null)
    })

    test('opens accessible dialog on mod+i', () => {
      assert.equal(accessibleDialog.open, false)
      source.value = ''
      ghost.textContent = 'suggested'
      manager.currentSuggestion = 'suggested'

      const event = new KeyboardEvent('keydown', {key: 'i', ctrlKey: true})
      source.dispatchEvent(event)

      assert.equal(source.value, '')
      assert.equal(ghost.textContent, 'suggested')
      assert.equal(accessibleDialog.open, true)
    })

    test('cancels suggestion', () => {
      source.value = ''
      ghost.textContent = 'suggested'
      manager.currentSuggestion = 'suggested'

      const event = new KeyboardEvent('keydown', {key: 'Escape'})
      source.dispatchEvent(event)

      assert.equal(source.value, '')
      assert.equal(ghost.textContent, '')
      assert.equal(manager.currentSuggestion, null)
    })
  })

  describe('keyup', () => {
    test('successful completion request', async () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      mockCompletion('yolo', [{text: 'yolo', tokens: ['yolo'], token_logprobs: [0], top_logprobs: [{yolo: 0}]}])

      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)

      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'yolo')
      assert.equal(ghost.textContent, 'testyolo\n')
    })

    test('failed completion request cancels', async () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      ghost.textContent = 'test suggestion'

      mockCompletion(undefined)

      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)

      assert.isFalse(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, null)
      assert.equal(ghost.textContent, '')
      assert.equal(source.value, 'test')
    })

    test('truncates by single-token confidence threshold at 10%', async () => {
      component.suggestionConfidenceThreshold = 0
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''
      mockCompletion('foobar response', [
        {text: 'foo', tokens: ['foo'], token_logprobs: [-0.2], top_logprobs: [{foo: -0.2}]}, // 81%
        {text: 'bar ', tokens: ['bar '], token_logprobs: [-0.2], top_logprobs: [{'bar ': -0.2}]}, // 81%
        {text: 'response', tokens: ['response'], token_logprobs: [-2.5], top_logprobs: [{response: -2.5}]}, // 8%
      ])
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'foobar ')
    })

    test('truncates by confidence threshold at 0%', async () => {
      component.suggestionConfidenceThreshold = 0
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''
      mockCompletion('foobar response', [
        {text: 'foo', tokens: ['foo'], token_logprobs: [-1.0], top_logprobs: [{foo: -1.0}]},
        {text: 'bar ', tokens: ['bar '], token_logprobs: [-1.0], top_logprobs: [{'bar ': -1.0}]},
        {text: 'response', tokens: ['response'], token_logprobs: [-1.0], top_logprobs: [{response: -1.0}]},
      ]) // 36% overall and per-token confidence
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'foobar response')
    })

    test('truncates by confidence threshold at 25%', async () => {
      component.suggestionConfidenceThreshold = 0.25
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''
      mockCompletion('foobar response', [
        {text: 'foo', tokens: ['foo'], token_logprobs: [-1.2], top_logprobs: [{foo: -1.2}]},
        {text: 'bar ', tokens: ['bar '], token_logprobs: [-1.2], top_logprobs: [{'bar ': -1.2}]},
        {text: 'response', tokens: ['response'], token_logprobs: [-3.0], top_logprobs: [{response: -3.0}]},
      ]) // 30% overall and per-token confidence until last token, then overall dips to 22%
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'foobar ')
    })

    test('truncates by confidence threshold (40%)', async () => {
      component.suggestionConfidenceThreshold = 0.4
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''

      mockCompletion('foobar response', [
        {text: 'foo', tokens: ['foo'], token_logprobs: [-0.6], top_logprobs: [{foo: -0.6}]},
        {text: 'bar ', tokens: ['bar '], token_logprobs: [-0.6], top_logprobs: [{'bar ': -0.6}]},
        {text: 'response', tokens: ['response'], token_logprobs: [-3.0], top_logprobs: [{response: -3.0}]},
      ]) // 54% overall and per-token confidence until last token, then overall dips to 37%
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'foobar ')
    })

    test('truncates by confidence threshold (55%)', async () => {
      component.suggestionConfidenceThreshold = 0.55
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''

      mockCompletion('foobar response', [
        {text: 'foo', tokens: ['foo'], token_logprobs: [-0.5], top_logprobs: [{foo: -0.5}]},
        {text: 'bar ', tokens: ['bar '], token_logprobs: [-0.5], top_logprobs: [{'bar ': -0.5}]},
        {text: 'response', tokens: ['response'], token_logprobs: [-3.0], top_logprobs: [{response: -3.0}]},
      ]) // 61% overall and per-token confidence until last token, then overall dips to 42%
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'foobar ')
    })

    test('truncates by confidence threshold (70%)', async () => {
      component.suggestionConfidenceThreshold = 0.7
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''

      mockCompletion('foobar response', [
        {text: 'foo', tokens: ['foo'], token_logprobs: [-0.3], top_logprobs: [{foo: -0.3}]},
        {text: 'bar ', tokens: ['bar '], token_logprobs: [-0.3], top_logprobs: [{'bar ': -0.3}]},
        {text: 'response', tokens: ['response'], token_logprobs: [-1.5], top_logprobs: [{response: -1.5}]},
      ]) // 74% overall and per-token confidence until last token, then overall dips to 57%
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isTrue(manager.hasSuggestion())
      assert.equal(manager.currentSuggestion, 'foobar ')
    })

    test('suppresses completions that are ripped from the static prompt', async () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      manager.currentSuggestion = ''
      mockCompletion('test', [
        {text: '(describe', tokens: ['(describe'], token_logprobs: [0], top_logprobs: [{'(describe': 0}]},
        {text: ' files', tokens: [' files'], token_logprobs: [0], top_logprobs: [{' files': 0}]},
        {text: ', ', tokens: [', '], token_logprobs: [0], top_logprobs: [{', ': 0}]},
        {text: 'what', tokens: ['what'], token_logprobs: [0], top_logprobs: [{what: 0}]},
        {text: ' was', tokens: [' was'], token_logprobs: [0], top_logprobs: [{' was': 0}]},
        {text: ' changed', tokens: [' changed'], token_logprobs: [0], top_logprobs: [{' changed': 0}]},
      ]) // 100% overall and per-token confidence
      const event = new KeyboardEvent('keyup', {key: 'Space'})
      await component.handleKeyUp(event, manager, context, source)
      assert.isFalse(manager.hasSuggestion())
    })
  })

  describe('accessible dialog close', () => {
    test('closes see more text toggle', () => {
      const hideFullText = spy(manager.screenReaderManager, 'hideFullText')
      const event = new Event('close')
      accessibleDialog.dispatchEvent(event)
      assert(hideFullText.calledOnce)
    })
  })

  describe('accessible dialog click', () => {
    test('accepts suggestion', () => {
      ghost.textContent = 'suggested'
      manager.currentSuggestion = 'suggested'

      const event = new Event('click')
      accessibleDialogAccept.dispatchEvent(event)

      assert.equal(source.value, 'suggested')
      assert.equal(ghost.textContent, '')
      assert.equal(manager.currentSuggestion, null)
    })

    test('rejects suggestion (and removes phantom newline)', () => {
      ghost.textContent = 'suggested\n'
      manager.currentSuggestion = 'suggested'

      const event = new Event('click')
      accessibleDialogReject.dispatchEvent(event)

      assert.equal(source.value, '')
      assert.equal(ghost.textContent, '')
      assert.equal(manager.currentSuggestion, null)
    })
  })

  describe('resizing', () => {
    test('clears the suggestion', () => {
      ghost.textContent = 'suggested'
      manager.currentSuggestion = 'suggested'
      component.handleResize()
      assert.equal(source.value, '')
      assert.equal(ghost.textContent, '')
      assert.equal(manager.currentSuggestion, null)
    })
  })
})
