import type {Icon} from '@primer/octicons-react'
import {ActionList, ActionMenu} from '@primer/react'
import {useEffect, useId, useRef} from 'react'
import type {Mode, ModeWithEditor} from '../types'
import Item from './Item'
import Title from './Title'
import Description from './Description'
import {Custom} from './Controls'

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
  labelId?: string
  descriptionId?: string
}

interface SelectorProps extends ModeSelectorProps {
  /** Title of the selection first row */
  title: string
  /** Description of the selection first row */
  description?: string
}

/**
 * A component that shows a container with multiple modes of selecting with a custom editor for each mode.
 * The first row shows the title and description, and the second row shows the editor for the selected mode.
 */
const Selector = ({title, description, modes, ...props}: SelectorProps) => {
  const shouldOpenRef = useRef(false)
  const mode = modes.find(m => m.name === props.selectedMode)

  const groupTitleId = useId()
  const groupDescriptionId = useId()
  const editorTitleId = useId()
  const editorDescriptionId = useId()

  const handleModeChange = (newMode: string) => {
    shouldOpenRef.current = true
    props.onModeChange?.(newMode)
  }

  useEffect(() => {
    shouldOpenRef.current = false
  }, [props.selectedMode])

  const firstMode = modes[0]
  if (modes.length === 1 && hasEditor(firstMode)) {
    return (
      <Item>
        <Title id={groupTitleId}>{title}</Title>
        <Description id={groupDescriptionId}>{description}</Description>
        <Custom>{firstMode.renderEditor({labelId: groupTitleId, descriptionId: groupDescriptionId})}</Custom>
      </Item>
    )
  }

  return (
    <>
      <Item>
        <Title id={groupTitleId}>{title}</Title>
        <Description id={groupDescriptionId}>{description}</Description>
        <Custom>
          <ModeSelector
            modes={modes}
            {...props}
            labelId={groupTitleId}
            descriptionId={groupDescriptionId}
            onModeChange={handleModeChange}
          />
        </Custom>
      </Item>
      {mode && hasEditor(mode) && (
        <Item>
          <Title id={editorTitleId}>{mode.editorLabel ?? mode.label}</Title>
          <Description id={editorDescriptionId}>{mode.editorDescription ?? mode.description}</Description>
          <Custom>
            {mode.renderEditor({
              shouldOpen: shouldOpenRef.current,
              labelId: editorTitleId,
              descriptionId: editorDescriptionId,
            })}
          </Custom>
        </Item>
      )}
    </>
  )
}

export default Selector

const ModeSelector = ({selectedMode, onModeChange, modes, selectorIcon, labelId, descriptionId}: ModeSelectorProps) => {
  const selectedModeObject = modes.find(m => m.name === selectedMode)
  const selectionTitleId = useId()

  return (
    <ActionMenu>
      <ActionMenu.Button
        leadingVisual={selectorIcon}
        aria-labelledby={`${labelId} ${selectionTitleId}`}
        aria-describedby={descriptionId}
      >
        <span id={selectionTitleId}>{selectedModeObject ? selectedModeObject.label : selectedMode}</span>
      </ActionMenu.Button>
      <ActionMenu.Overlay style={{width: 'max-content', maxWidth: '500px'}}>
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

const hasEditor = (mode?: Mode): mode is ModeWithEditor => {
  return (mode as ModeWithEditor)?.renderEditor !== undefined
}
