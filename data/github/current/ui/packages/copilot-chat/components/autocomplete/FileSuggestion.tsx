import {FileDirectoryFillIcon, FileIcon} from '@primer/octicons-react'
import {ActionList, type ActionListItemProps} from '@primer/react'
import {clsx} from 'clsx'

import sharedStyles from './shared.module.css'

interface FileSuggestionProps extends ActionListItemProps {
  type: 'file' | 'folder'
  path: string
  stale?: boolean
}

export function FileSuggestion({type, path, stale, className, ...props}: FileSuggestionProps) {
  const parts = path.split('/')
  const name = parts.pop()!

  return (
    <ActionList.Item {...props} className={clsx(sharedStyles.asyncSuggestion, stale && sharedStyles.stale, className)}>
      <ActionList.LeadingVisual>
        {type === 'folder' ? <FileDirectoryFillIcon /> : <FileIcon />}
      </ActionList.LeadingVisual>
      {name}
      <ActionList.Description variant="inline">{parts.join('/')}/</ActionList.Description>
    </ActionList.Item>
  )
}
