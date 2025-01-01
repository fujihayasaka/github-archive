import {getWorkerUrl} from '../webpack-worker'
import type {MonacoWorkerUrls} from '../workspace-editor-types'

const urls: MonacoWorkerUrls = {
  editor: '/assets-cdn/worker/monaco-editor-worker-d515ed7d995e.js',
  css: '/assets-cdn/worker/monaco-css-worker-e89ae32b15dc.js',
  html: '/assets-cdn/worker/monaco-html-worker-19359e8ec0b5.js',
  json: '/assets-cdn/worker/monaco-json-worker-52499dcc1605.js',
  ts: '/assets-cdn/worker/monaco-ts-worker-ac36ff729e9c.js',
}

describe('getWorkerUrl', () => {
  it('returns the correct URL for json', () => {
    expect(getWorkerUrl('json', urls)).toBe('/assets-cdn/worker/monaco-json-worker-52499dcc1605.js')
  })

  it('returns the correct URL for css', () => {
    expect(getWorkerUrl('css', urls)).toBe('/assets-cdn/worker/monaco-css-worker-e89ae32b15dc.js')
  })

  it('returns the correct URL for html', () => {
    expect(getWorkerUrl('html', urls)).toBe('/assets-cdn/worker/monaco-html-worker-19359e8ec0b5.js')
  })

  it('returns the correct URL for typescript', () => {
    expect(getWorkerUrl('typescript', urls)).toBe('/assets-cdn/worker/monaco-ts-worker-ac36ff729e9c.js')
  })

  it('returns the correct URL for javascript', () => {
    expect(getWorkerUrl('javascript', urls)).toBe('/assets-cdn/worker/monaco-ts-worker-ac36ff729e9c.js')
  })

  it('returns the editor URL for unknown labels', () => {
    expect(getWorkerUrl('unknown', urls)).toBe('/assets-cdn/worker/monaco-editor-worker-d515ed7d995e.js')
    expect(getWorkerUrl('', urls)).toBe('/assets-cdn/worker/monaco-editor-worker-d515ed7d995e.js')
  })
})
