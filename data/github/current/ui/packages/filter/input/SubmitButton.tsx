import {SearchIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'

import {useFilterQuery} from '../context'
import {SubmitEvent} from '../types'
import styles from './SubmitButton.module.css'

export const SubmitButton = () => {
  const {onSubmit} = useFilterQuery()

  return (
    <IconButton
      aria-label="Search"
      size="medium"
      icon={SearchIcon}
      variant="default"
      onClick={() => {
        onSubmit(SubmitEvent.ExplicitSubmit, 'input_with_button')
      }}
      className={styles.IconButton_0}
    />
  )
}
