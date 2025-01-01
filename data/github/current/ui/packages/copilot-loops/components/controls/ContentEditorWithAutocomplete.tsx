import {ContentEditor} from './ContentEditor'
import type {Extension} from '@codemirror/state'
import {createNodeAutocompleteExtension} from '../../utils/code-mirror-extensions/node-autocomplete'
import {useLoopLens} from '../../hooks/use-loop-lens'

export const ContentEditorWithAutocomplete = ({
  className,
  content,
  onUpdate,
  placeholder = 'Enter a prompt',
  extensions,
  nodeId,
  inputLabelId,
}: {
  className?: string
  content: string
  onUpdate?: (content: string) => void
  placeholder?: string
  extensions?: Extension[]
  nodeId?: string
  inputLabelId: string
}) => {
  const nodes = useLoopLens(pipeline => pipeline?.nodes ?? [])
  const nodeAutocomplete = createNodeAutocompleteExtension(() => nodes, nodeId)
  const allExtensions = [...(extensions ?? []), nodeAutocomplete]

  return (
    <ContentEditor
      className={className}
      content={content}
      onUpdate={onUpdate}
      placeholder={placeholder}
      extensions={allExtensions}
      inputLabelId={inputLabelId}
    />
  )
}
