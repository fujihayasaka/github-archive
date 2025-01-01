import {EditorView} from '@codemirror/view'
import type {Screen} from '@testing-library/react'

export function getCodeMirrorInstance(screen: Screen, selector: string = 'codemirror-editor') {
  const editorInput = screen.getByTestId(selector)

  // eslint-disable-next-line testing-library/no-node-access
  const editorView = editorInput.querySelector<HTMLElement>('.cm-content')!

  return EditorView.findFromDOM(editorView)!
}

export function typeInCodeMirror(view: EditorView, text: string) {
  view.focus()

  const cur = view.state.selection.main.head
  view.dispatch({changes: {from: cur, insert: text}, selection: {anchor: cur + text.length}, userEvent: 'input.type'})
}

export function deleteForward(view: EditorView) {
  const cur = view.state.selection.main.head
  view.dispatch({changes: {from: cur, to: cur + 1}, userEvent: 'delete'})
}
