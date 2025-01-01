import {ControlGroup} from '@github-ui/control-group'
import type {Icon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import type React from 'react'

interface SelectionProps extends ModeSelectorProps {
  /** Title of the selection first row */
  title: string
  /** Description of the selection first row */
  description: string
}

interface ModeSelectorProps {
  /** Icon to show in the mode selector in the first row */
  selectorIcon?: Icon
  /** The currently selected mode */
  selectedMode?: string
  /** Callback when the mode changes */
  onModeChange?(mode: string): void
  /**
   * The available mode options. If there's only one, selector dropdown is not displayed
   * and the mode editor is shown directly in the first row.
   */
  modes: Mode[]
}

type Mode = ModeWithoutEditor | ModeWithEditor

interface ModeWithoutEditor {
  /** The internal name of the mode */
  name: string
  /** The label to show for this mode in the selector dropdown */
  label: string
  /** The description to show for this mode in the selector dropdown */
  description?: string
}

interface ModeWithEditor extends ModeWithoutEditor {
  /** The custom editor to show in the second row */
  renderEditor(): React.ReactNode
  /** The label to show in the second row when this mode is selected */
  editorLabel?: string
  /** The description to show in the second row when this mode is selected */
  editorDescription?: string
}

/**
 * A component that shows a container with multiple modes of selecting with a custom editor for each mode.
 * The first row shows the title and description, and the second row shows the editor for the selected mode.
 */
export function Selection({title, description, modes, ...props}: SelectionProps) {
  const mode = modes.find(m => m.name === props.selectedMode)

  const firstMode = modes[0]
  if (modes.length === 1 && hasEditor(firstMode!)) {
    return (
      <ControlGroup>
        <ControlGroup.Item>
          <ControlGroup.Title>{title}</ControlGroup.Title>
          <ControlGroup.Description>{description}</ControlGroup.Description>
          <ControlGroup.Custom>{firstMode.renderEditor()}</ControlGroup.Custom>
        </ControlGroup.Item>
      </ControlGroup>
    )
  }

  return (
    <ControlGroup>
      <ControlGroup.Item>
        <ControlGroup.Title>{title}</ControlGroup.Title>
        <ControlGroup.Description>{description}</ControlGroup.Description>
        <ControlGroup.Custom>
          <ModeSelector modes={modes} {...props} />
        </ControlGroup.Custom>
      </ControlGroup.Item>
      {mode && hasEditor(mode) && (
        <ControlGroup.Item>
          <ControlGroup.Title>{mode.editorLabel || mode.label}</ControlGroup.Title>
          <ControlGroup.Description>{mode.editorDescription || mode.description}</ControlGroup.Description>
          <ControlGroup.Custom>{mode.renderEditor()}</ControlGroup.Custom>
        </ControlGroup.Item>
      )}
    </ControlGroup>
  )
}

const ModeSelector = ({selectedMode, onModeChange, modes, selectorIcon}: ModeSelectorProps) => {
  const selectedModeObject = modes.find(m => m.name === selectedMode)

  return (
    <ActionMenu>
      <ActionMenu.Button leadingVisual={selectorIcon}>
        {selectedModeObject ? selectedModeObject.label : selectedMode}
      </ActionMenu.Button>
      <ActionMenu.Overlay width="medium">
        <ActionList selectionVariant="single">
          {modes.map(mode => (
            <ActionList.Item
              key={mode.name}
              selected={mode.name === selectedMode}
              onSelect={() => onModeChange?.(mode.name)}
            >
              {mode.label}
              {mode.description && <ActionList.Description variant="block">{mode.description}</ActionList.Description>}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}

function hasEditor(mode: Mode): mode is ModeWithEditor {
  return (mode as ModeWithEditor).renderEditor !== undefined
}
