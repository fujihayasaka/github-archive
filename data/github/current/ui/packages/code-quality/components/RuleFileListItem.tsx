import {FileIcon} from '@primer/octicons-react'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ListItem} from '@github-ui/list-view/ListItem'
import type {RuleFile} from '../types/rule-file'
import {CounterLabel} from '@primer/react'

import styles from './RuleFileListItem.module.css'

export type RuleFileListItemProps = {
  file: RuleFile
}

export function RuleFileListItem({file}: RuleFileListItemProps) {
  return (
    <ListItem
      title={
        <ListItemTitle
          value={file.filePath}
          headingClassName={styles.content}
          trailingBadges={
            file.findingsCount > 1 ? [<CounterLabel key="counter">{file.findingsCount}</CounterLabel>] : []
          }
        />
      }
    >
      <ListItemLeadingContent className={styles.content}>
        <ListItemLeadingVisual icon={FileIcon} description="File" color="fg.muted" />
      </ListItemLeadingContent>
    </ListItem>
  )
}
