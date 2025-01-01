import type {ChangeEvent, MouseEvent} from 'react'
import styles from './EditableText.module.css'
import {TextInput} from '@primer/react'
import {clsx} from 'clsx'

interface EditableTextProps {
  className?: string
  isEditable?: boolean
  onChange: (newText: string) => void
  onClick?: (e: MouseEvent) => void
  value: string
}

export function EditableText({value, className, isEditable = true, onChange, onClick}: EditableTextProps) {
  const handleChange = (e: ChangeEvent<HTMLInputElement>) => {
    onChange(e.target.value)
  }

  if (!isEditable) {
    return <div className={clsx(styles.view, className)}>{value}</div>
  }

  return (
    <TextInput
      type="text"
      value={value}
      onChange={handleChange}
      onClick={onClick}
      className={clsx(styles.input, className)}
    />
  )
}
