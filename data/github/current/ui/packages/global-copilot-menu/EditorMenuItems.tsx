import {ActionList} from '@primer/react'
import editors from './editors'

interface EditorMenuItemProps {
  onClick?: (editorId: string) => void
}

export function EditorMenuItems({onClick}: EditorMenuItemProps) {
  return Object.entries(editors).map(([key, {name, url, icon}]) => (
    <ActionList.LinkItem key={key} href={url} onClick={() => onClick?.(key)}>
      {name}
      <ActionList.LeadingVisual>
        {/* Icons should not have alt text since they are decorative and redundant with the editor name */}
        <img src={icon} alt="" height="20" width="20" />
      </ActionList.LeadingVisual>
    </ActionList.LinkItem>
  ))
}
