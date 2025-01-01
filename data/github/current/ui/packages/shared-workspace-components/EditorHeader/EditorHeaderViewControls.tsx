import {CodeIcon, FileIcon, MirrorIcon} from '@primer/octicons-react'
import {SegmentedControl} from '@primer/react'
import {memo} from 'react'

const EditorMode = {
  Edit: 0,
  Preview: 1,
  Split: 2,
} as const

type EditorMode = (typeof EditorMode)[keyof typeof EditorMode]

export const EditorHeaderViewControls = memo(function HeaderActions({
  editorMode,
  isDeleted,
  isPreviewable = false,
  updateEditorMode,
}: {
  editorMode?: EditorMode
  isDeleted: boolean
  isPreviewable?: boolean
  updateEditorMode?: (index: number) => void
}) {
  const isSelected = (mode: EditorMode) => editorMode === mode

  return !isDeleted && isPreviewable ? (
    <SegmentedControl aria-label="File view" onChange={updateEditorMode}>
      <SegmentedControl.IconButton icon={CodeIcon} aria-label="Edit code" selected={isSelected(EditorMode.Edit)} />
      <SegmentedControl.IconButton
        icon={FileIcon}
        aria-label="Preview file"
        selected={isSelected(EditorMode.Preview)}
      />
      <SegmentedControl.IconButton icon={MirrorIcon} aria-label="Split view" selected={isSelected(EditorMode.Split)} />
    </SegmentedControl>
  ) : null
})
