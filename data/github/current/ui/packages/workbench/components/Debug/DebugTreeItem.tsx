import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {TreeView} from '@primer/react'

import styles from './DebugTreeItem.module.css'

type SomeData = string | boolean | undefined | number | object

const getDataString = (d: SomeData) => {
  if (typeof d === 'boolean') {
    return d ? 'true' : 'false'
  } else if (typeof d === 'object') {
    return JSON.stringify(d, null, 2)
  } else if (typeof d === 'number') {
    return d.toString()
  }
  return d ?? 'undefined'
}

export interface DebugTreeItemProps {
  label: string
  data: SomeData
  id: number
}

export const DebugTreeItem = ({label, data, id}: DebugTreeItemProps) => {
  return (
    <TreeView.Item id={`node-${id}`}>
      <TreeView.LeadingVisual>
        <CopyToClipboardButton textToCopy={getDataString(data)} size="small" />
      </TreeView.LeadingVisual>
      <div className={styles.valueLabel}>{label}:</div>
      <div className={styles.value}>{getDataString(data)}</div>
    </TreeView.Item>
  )
}
