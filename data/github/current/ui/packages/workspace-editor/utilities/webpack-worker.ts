import type {MonacoWorkerUrls} from './workspace-editor-types'

/**
 * Gets the URL to use for a Monaco worker.
 */
export function getWorkerUrl(label: string, monacoEditorUrls: MonacoWorkerUrls) {
  switch (label) {
    case 'json':
      return monacoEditorUrls.json
    case 'css':
      return monacoEditorUrls.css
    case 'html':
      return monacoEditorUrls.html
    case 'typescript':
    case 'javascript':
      return monacoEditorUrls.ts
    default:
      return monacoEditorUrls.editor
  }
}
