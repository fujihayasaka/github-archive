import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {Stack} from '@primer/react'

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
}

export const DebugBasicItem = ({label, data}: DebugTreeItemProps) => {
  const dataString = getDataString(data)
  return (
    <Stack direction="horizontal" gap="condensed">
      <CopyToClipboardButton textToCopy={dataString} size="small" />

      <span className={styles.valueLabel}>{label}:</span>

      <span className={styles.value}>{dataString}</span>
    </Stack>
  )
}
