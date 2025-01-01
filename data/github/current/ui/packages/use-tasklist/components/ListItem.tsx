import type {ListItem} from '@github-ui/markdown-editor/list-editing'
import {UnsafeHTMLBox} from '@github-ui/safe-html/UnsafeHTML'
import type {TaskItem} from '../constants/types'

export type ListItemProps = {
  item: TaskItem
  position: number
}

export function ListItem({item, position}: ListItemProps) {
  const tasklistIstemTestIdBase = `tasklist-item-${position}-${item.markdownIndex}`

  return (
    <UnsafeHTMLBox
      // Added to reserve space to match the styling of checkbox list items
      sx={{mr: 6}}
      html={item.content}
      as={'div'}
      data-testid={tasklistIstemTestIdBase}
    />
  )
}
