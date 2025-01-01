import type {ProgressBarProps as PrimerProgressBarProps} from '@primer/react'
import {ProgressBar as PrimerProgressBar} from '@primer/react'
import {ColorByIndex} from './Shared'

import styles from './ProgressBar.module.css'

interface Item {
  progress: number
  color?: string
  label?: string
}

export interface ProgressBarProps extends Omit<PrimerProgressBarProps, 'progress'> {
  data: Item[]
}

function ProgressBar(props: ProgressBarProps) {
  function renderItems() {
    return props.data.map((item, index) => {
      const color = item.color ?? ColorByIndex(index)
      const label = item.label

      return (
        <PrimerProgressBar.Item
          role="progressbar"
          // eslint-disable-next-line @eslint-react/no-array-index-key
          key={index}
          progress={item.progress}
          sx={{backgroundColor: color}}
          aria-label={label}
        />
      )
    })
  }

  function valueNow() {
    return props.data.reduce((acc, item) => acc + item.progress, 0)
  }

  return (
    <PrimerProgressBar
      aria-valuenow={valueNow()}
      aria-label={props['aria-label']}
      sx={{
        ...props.sx,
      }}
      className={styles.PrimerProgressBar}
    >
      {renderItems()}
    </PrimerProgressBar>
  )
}

ProgressBar.displayName = 'DataCard.ProgressBar'

ProgressBar.Item = PrimerProgressBar.Item

export default ProgressBar
