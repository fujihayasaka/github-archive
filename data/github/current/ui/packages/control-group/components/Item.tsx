import {useSlots} from '@primer/react/experimental'
import Title from './Title'
import Description from './Description'
import {Button, InlineEdit, ToggleSwitch, Custom} from './Controls'
import styles from './Item.module.css'
import {clsx} from 'clsx'
import type {CSSProperties} from 'react'

export type ControlGroupItemProps = {
  children: React.ReactNode
  nestedLevel?: 0 | 1 | 2
  disabled?: boolean
}

const slotConfig = {
  title: Title,
  description: Description,
  custom: Custom,
  toggle: ToggleSwitch,
  button: Button,
  inlineEdit: InlineEdit,
}

const Item = ({children, nestedLevel = 0, disabled = false}: ControlGroupItemProps) => {
  const [{title, description, custom, toggle, button, inlineEdit}] = useSlots(children, slotConfig)

  const blockControl = button || inlineEdit || custom
  const inlineControl = toggle

  return (
    <div
      className={clsx('controlBoxContainer', styles.container, disabled && styles.disabled)}
      style={{'--nested-level': nestedLevel} as CSSProperties}
    >
      <div className={styles.contents}>
        {title && <div className={clsx(styles.title, 'titleBox')}>{title}</div>}
        {description && <div className={clsx(styles.description, 'descriptionBox')}>{description}</div>}
        {blockControl && <div className={clsx(styles.blockControl, 'blockControl')}>{blockControl}</div>}
        {inlineControl && <div className={clsx(styles.inlineControl, 'inlineControl')}>{inlineControl}</div>}
      </div>
    </div>
  )
}

export default Item
