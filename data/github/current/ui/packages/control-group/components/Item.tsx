import {useSlots} from '@primer/react/experimental'
import Title from './Title'
import Description from './Description'
import {Button, InlineEdit, ToggleSwitch, Custom} from './Controls'
import styles from './Item.module.css'
import {clsx} from 'clsx'

export type ControlGroupItemProps = {
  children: React.ReactNode
  nestedLevel?: 0 | 1 | 2
  disabled?: boolean
  contentsClassname?: string
}

const slotConfig = {
  title: Title,
  description: Description,
  custom: Custom,
  toggle: ToggleSwitch,
  button: Button,
  inlineEdit: InlineEdit,
}

const Item = ({children, nestedLevel = 0, disabled = false, contentsClassname}: ControlGroupItemProps) => {
  const [{title, description, custom, toggle, button, inlineEdit}] = useSlots(children, slotConfig)

  const blockControl = button || inlineEdit || custom || toggle

  return (
    <div
      className={clsx('controlBoxContainer', styles.container, disabled && styles.disabled)}
      style={{'--nested-level': nestedLevel}}
    >
      <div className={clsx(styles.contents, contentsClassname)}>
        {title && <div className={clsx(styles.title, 'titleBox')}>{title}</div>}
        {description && <div className={clsx(styles.description, 'descriptionBox')}>{description}</div>}
        {blockControl && <div className={clsx(styles.blockControl, 'blockControl')}>{blockControl}</div>}
      </div>
    </div>
  )
}

export default Item
