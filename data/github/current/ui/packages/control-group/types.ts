import type React from 'react'

interface ModeWithoutEditor {
  /** The internal name of the mode */
  name: string
  /** The label to show for this mode in the selector dropdown */
  label: string
  /** The description to show for this mode in the selector dropdown */
  description?: string
}

interface RenderEditorArgs {
  /** Whether the editor should be immediately opened or not. Defaults to false */
  shouldOpen?: boolean
  labelId?: string
  descriptionId?: string
}

export interface ModeWithEditor extends ModeWithoutEditor {
  /** The custom editor to show in the second row */
  renderEditor(args: RenderEditorArgs): React.ReactNode
  /** The label to show in the second row when this mode is selected */
  editorLabel?: string
  /** The description to show in the second row when this mode is selected */
  editorDescription?: React.ReactNode
}

export type Mode = ModeWithoutEditor | ModeWithEditor
