import {
  BookIcon,
  ChecklistIcon,
  PencilIcon,
  ToolsIcon,
  EyeIcon,
  PlayIcon,
  ShieldIcon,
  NoteIcon,
  type Icon,
} from '@primer/octicons-react'
import type {ReactElement} from 'react'

// Used for mapping octicon names to their respective Icon components. This list is non-comprehensive and
// should be expanded to match the possible `.octicon` values that Roles can have.
// This currently includes the icons for pre-defined roles from:
// - packages/app_security/app/models/organization_role.rb
const IconMap: Record<string, Icon> = {
  book: BookIcon,
  checklist: ChecklistIcon,
  pencil: PencilIcon,
  tools: ToolsIcon,
  eye: EyeIcon,
  play: PlayIcon,
  shield: ShieldIcon,
  note: NoteIcon,
}

export default function getRoleIcon(roleIcon: string): ReactElement {
  const IconComponent = IconMap[roleIcon] || NoteIcon
  return <IconComponent />
}
