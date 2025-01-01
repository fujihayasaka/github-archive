import {afterEach, beforeEach, describe, it} from '@github-ui/tests'
import {assert, fixture, html} from '@github-ui/tests/browser'
import {GhostManagerV2} from '../ghost-manager-v2'
import type {TextRuler} from '../text-ruler'
import {ScreenReaderManager} from '../screen-reader-manager'
import {spy, stub, restore} from 'sinon'

import {featureFlag} from '@github-ui/feature-flags'
import {GhostTextArea} from '../ghost'

describe("Ghost Manager's office is always open", () => {
  let source: HTMLTextAreaElement
  let ghost: HTMLTextAreaElement
  let ruler: TextRuler
  let manager: GhostManagerV2

  beforeEach(async function () {
    stub(featureFlag, 'isFeatureEnabled').returns(true)
    const markup = await fixture(
      html`<file-attachment class="is-default">
        <textarea id="source"></textarea><textarea id="ghost"></textarea>
      </file-attachment>`,
    )
    source = markup.querySelector('#source')!
    ghost = markup.querySelector('#ghost')!
    ruler = {
      // For our testing don't bother with wrapping that needs a real textarea
      // (which the fixture doesn't do properly). Just count newlines
      getNumberOfLines: (text: string) => text.split('\n').length,
    }
    const screenReaderManager = new ScreenReaderManager(undefined, undefined, undefined)
    manager = new GhostManagerV2(source, new GhostTextArea(ghost), ruler, screenReaderManager)
    source.focus()
  })

  afterEach(() => {
    restore()
  })

  describe('hasSuggestion', () => {
    it('no suggestion', () => {
      manager.currentSuggestion = null
      assert.isFalse(manager.hasSuggestion())
    })

    it('as suggested', () => {
      manager.currentSuggestion = 'try this'
      assert.isTrue(manager.hasSuggestion())
    })
  })

  // Most permutation testing delegated to helper it uses
  describe('shouldCompleteHere', () => {
    it('sure ', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = source.value.length
      assert.isTrue(manager.shouldCompleteHere())
    })

    it('notWithMultiCharacterHighlight', () => {
      source.value = 'text'
      source.selectionStart = 0
      source.selectionEnd = 1
      assert.isFalse(manager.shouldCompleteHere())
    })

    it('notAtNewLine', () => {
      source.value = 'text\n'
      source.selectionStart = source.selectionEnd = 1
      assert.isFalse(manager.shouldCompleteHere())
    })

    it('notAtEnd', () => {
      source.value = 'text'
      source.selectionStart = source.selectionEnd = 1
      assert.isFalse(manager.shouldCompleteHere())
    })

    it('notEmpty', () => {
      source.value = ''
      source.selectionStart = 0
      source.selectionEnd = 0
      assert.isFalse(manager.shouldCompleteHere())
    })

    it('atNewLine', () => {
      source.value = 'text\n'
      source.selectionStart = source.selectionEnd = 4
      assert.isTrue(manager.shouldCompleteHere())
    })

    it('atEnd', () => {
      source.value = 'text'
      source.selectionStart = source.selectionEnd = source.value.length
      assert.isTrue(manager.shouldCompleteHere())
    })

    it('while waiting on file upload', () => {
      source.value = 'text'
      source.selectionStart = source.selectionEnd = source.value.length
      const fileAttachment = document.querySelector('file-attachment')
      fileAttachment!.className = 'is-uploading'
      assert.isFalse(manager.shouldCompleteHere())
    })

    it('while waiting on a copilot outline', () => {
      source.value = '[Copilot is generating an outline...]'
      source.selectionStart = source.selectionEnd = source.value.length
      assert.isFalse(manager.shouldCompleteHere())
    })

    it('while waiting on a copilot summary', () => {
      source.value = '[Copilot is generating a summary...]'
      source.selectionStart = source.selectionEnd = source.value.length
      assert.isFalse(manager.shouldCompleteHere())
    })
  })

  describe('showCompletion', () => {
    it('basic suggestion', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!'
      manager.showCompletion(suggestion, 4, 'context')

      assert.isTrue(manager.hasSuggestion())
      assert.equal(source.value, 'test')
      assert.equal(source.selectionStart, 4)
      assert.equal(ghost.value, 'testing!')
      assert.equal(ghost.scrollTop, source.scrollTop)
      assert.equal(manager.currentRawContext, 'context')
    })

    it('multiline suggestion', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!\nMatters!'
      manager.showCompletion(suggestion, 4, 'context')

      assert.isTrue(manager.hasSuggestion())
      assert.equal(source.value, 'test\n')
      assert.equal(source.selectionStart, 4)
      assert.equal(ghost.value, 'testing!\nMatters!')
      assert.equal(ghost.scrollTop, source.scrollTop)
      assert.equal(manager.currentRawContext, 'context')
    })

    it('last suggestion wins', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const ignoredSuggestion = 'ing!\nMatters!'
      manager.showCompletion(ignoredSuggestion, 4, 'old')

      const suggestion = 'ing!\nIs hard!'
      manager.showCompletion(suggestion, 4, 'new')

      assert.isTrue(manager.hasSuggestion())
      assert.equal(source.value, 'test\n')
      assert.equal(source.selectionStart, 4)
      assert.equal(ghost.value, 'testing!\nIs hard!')
      assert.equal(ghost.scrollTop, source.scrollTop)
      assert.equal(manager.currentRawContext, 'new')
    })

    it('calls screen reader manager', () => {
      const screenReaderCompletion = spy(manager.screenReaderManager, 'receivedCompletion')
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!'
      manager.showCompletion(suggestion, 4, 'context')
      assert(screenReaderCompletion.withArgs(suggestion, `${source.value}${suggestion}`).calledOnce)
    })
  })

  describe('acceptSuggestion', () => {
    it('basic acceptance', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!'
      manager.showCompletion(suggestion, 4, 'context')
      manager.acceptSuggestion()

      assert.isFalse(manager.hasSuggestion())
      assert.equal(manager.currentRawContext, null)

      assert.equal(source.value, 'testing!')
      assert.equal(source.selectionStart, 8)
      assert.equal(ghost.value, '')
      assert.equal(ghost.scrollTop, source.scrollTop)
    })

    it('multi-line acceptance', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!\nMatters!'
      manager.showCompletion(suggestion, 4, 'context')
      manager.acceptSuggestion()

      assert.isFalse(manager.hasSuggestion())
      assert.equal(manager.currentRawContext, null)

      assert.equal(source.value, 'testing!\nMatters!')
      assert.equal(source.selectionStart, 17)
      assert.equal(ghost.value, '')
      assert.equal(ghost.scrollTop, source.scrollTop)
    })
  })

  describe('cancelSuggestion', () => {
    it('no suggestion active', () => {
      ghost.value = 'test'
      const cancelled = manager.cancelSuggestion()
      assert.isFalse(cancelled)
      assert.equal(ghost.value, '')
    })

    it('basic cancellation', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!'
      manager.showCompletion(suggestion, 4, 'context')
      const cancelled = manager.cancelSuggestion()

      assert.isTrue(cancelled)
      assert.isFalse(manager.hasSuggestion())
      assert.equal(source.value, 'test')
      assert.equal(source.selectionStart, 4)
      assert.equal(ghost.value, '')
      assert.equal(ghost.scrollTop, source.scrollTop)
    })

    it('multi-line cancellation', () => {
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4
      const suggestion = 'ing!\nMatters!'
      manager.showCompletion(suggestion, 4, 'context')
      const cancelled = manager.cancelSuggestion()

      assert.isTrue(cancelled)
      assert.isFalse(manager.hasSuggestion())
      assert.equal(source.value, 'test')
      assert.equal(source.selectionStart, 4)
      assert.equal(ghost.value, '')
      assert.equal(ghost.scrollTop, source.scrollTop)
    })

    it('calls screen reader manager', () => {
      const screenReaderClear = spy(manager.screenReaderManager, 'cancelSuggestion')
      source.value = 'test'
      source.selectionStart = source.selectionEnd = 4

      const suggestion = 'ing!'
      manager.showCompletion(suggestion, 4, 'context')
      manager.cancelSuggestion()

      assert(screenReaderClear.calledTwice)
    })
  })

  describe('handleNewlineSpacing', () => {
    beforeEach(async function () {
      ruler = {
        // Count number of lines by sentences, this lets us mock the word wrap scenario by using a period in the suggestion.
        getNumberOfLines: (text: string) => text.split('.').length,
      }
      const screenReaderManager = new ScreenReaderManager(undefined, undefined, undefined)
      manager = new GhostManagerV2(source, new GhostTextArea(ghost), ruler, screenReaderManager)
    })

    it('adds newline to source text when completion results in word wrap', () => {
      const prefix = 'Here is one sentence (and line). Here is another. Now lets test the end of a third sen'
      source.value = prefix
      manager.handleNewlineSpacing(prefix, 'tence.', 3, 4, true)
      assert.equal(
        source.value,
        'Here is one sentence (and line). Here is another. Now lets test the end of a third \nsen',
      )
    })

    it('does not add a newline when suggestion does not result in word wrap', () => {
      const prefix = 'Here is one sentence (and line). Here is another. Now lets test the end of a third sen'
      source.value = prefix
      manager.handleNewlineSpacing(prefix, "tence that isn't finished", 3, 3, true)
      assert.equal(source.value, prefix)
    })

    it('adds a newline when at the end of the line', async () => {
      const prefix = 'Here is one sentence (and line). Here is another. Now lets test the end of a third '
      const suggestion = 'sentence. This suggestion continues for many more lines.'
      source.value = prefix
      manager.currentSuggestion = suggestion
      manager.handleNewlineSpacing(prefix, suggestion, 3, 5, true)
      assert.equal(
        source.value,
        'Here is one sentence (and line). Here is another. Now lets test the end of a third \n\n',
      )
      assert.isTrue(manager.hasSuggestion())
      manager.cancelSuggestion()
      assert.equal(source.value, prefix)
    })
  })
})
