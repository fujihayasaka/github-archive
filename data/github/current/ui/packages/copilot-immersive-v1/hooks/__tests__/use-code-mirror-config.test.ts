import type {File} from '../../components/ContentPreview/content-preview-types'
import {guessCodeMirrorSettings} from '../use-code-mirror-config'

const makeFile = (value: string): File => ({
  value,
  name: 'test.js',
  language: 'javascript',
  type: 'file',
  isStreaming: false,
  isUserEdited: false,
  id: 'file:test.js#1.1',
  timestamp: new Date(0),
  messageId: 'messageId',
})

const tabFile = makeFile(`
function foo() {
	return "bar"
}`)

const twoSpaceFile = makeFile(`
function foo() {
  return "bar"
}`)

const fourSpaceFile = makeFile(`
function foo() {
    return "bar"
}`)

test('detects tabs', () => {
  expect(guessCodeMirrorSettings(tabFile)).toEqual({
    indentUnit: 8,
    indentWithTabs: true,
    lineWrapping: false,
  })
})

test('detects two spaces', () => {
  expect(guessCodeMirrorSettings(twoSpaceFile)).toEqual({
    indentUnit: 2,
    indentWithTabs: false,
    lineWrapping: false,
  })
})

test('detects four spaces', () => {
  expect(guessCodeMirrorSettings(fourSpaceFile)).toEqual({
    indentUnit: 4,
    indentWithTabs: false,
    lineWrapping: false,
  })
})
