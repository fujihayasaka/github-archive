import type {EditorStateConfig, Extension} from '@codemirror/state'
import {type EditorView, type KeyBinding, type ViewUpdate, keymap} from '@codemirror/view'
import {forwardRef, useImperativeHandle, useMemo, useRef} from 'react'

import {useCodeMirror} from './hooks/use-code-mirror'

export interface CodeMirrorProps extends Omit<EditorStateConfig, 'doc' | 'extensions'> {
  value?: string
  height?: string
  minHeight?: string
  width?: string
  fileName?: string
  placeholder?: string
  ariaLabelledBy: string

  extensions?: readonly Extension[]
  keyBindings?: readonly KeyBinding[]
  spacing: SpacingOptions
  focusNextRenderRef?: React.MutableRefObject<boolean>

  // after CM6 is stable and the default experience
  // consumers will pass extensions in instead of prop based
  enableFileUpload?: boolean
  isHpc?: boolean
  isReadOnly?: boolean
  hideHelpUntilFocus?: boolean
  hideHelp?: boolean

  containerClassName?: string

  /** Fired whenever a change occurs to the document. */
  onChange(newValue: string): void
  /** Fired whenever any state change occurs within the editor, including non-document changes like lint results. */
  onUpdate?(viewUpdate: ViewUpdate): void
  /** Fired when the editor is created. */
  onCreateEditor?(view: EditorView): void
  /** Fired when the editor is destroyed. */
  onDestroyEditor?(view: EditorView): void
}

export interface SpacingOptions {
  indentUnit: number
  indentWithTabs: boolean
  lineWrapping: boolean
}

export interface CodeMirrorRef {
  editor?: HTMLDivElement | null
  view?: EditorView
}

const EMPTY_EXTENSION_ARRAY: readonly Extension[] = []
const EMPTY_KEY_BINDING_ARRAY: readonly KeyBinding[] = []

const CodeMirror = forwardRef<CodeMirrorRef, CodeMirrorProps>((props, ref) => {
  const {
    value = '',
    extensions = EMPTY_EXTENSION_ARRAY,
    keyBindings = EMPTY_KEY_BINDING_ARRAY,
    height = '85vh',
    width = '100%',
    focusNextRenderRef,
    containerClassName,
    ...rest
  } = props
  const editorRef = useRef<HTMLDivElement>(null)

  const memoedExtensions = useMemo(() => [...extensions, keymap.of(keyBindings)], [extensions, keyBindings])

  const viewRef = useCodeMirror({
    parentRef: editorRef,
    value,
    height,
    width,
    extensions: memoedExtensions,
    ...rest,
  })

  useImperativeHandle(ref, () => ({editor: editorRef.current, view: viewRef.current}), [editorRef, viewRef])

  if (focusNextRenderRef?.current && viewRef) {
    window.requestAnimationFrame(() => {
      if (viewRef.current && !viewRef.current.hasFocus) {
        viewRef.current.focus()
      }
    })
    // eslint-disable-next-line react-hooks/react-compiler
    focusNextRenderRef.current = false
  }

  return <div className={containerClassName} ref={editorRef} />
})

CodeMirror.displayName = 'CodeMirror'

export default CodeMirror
