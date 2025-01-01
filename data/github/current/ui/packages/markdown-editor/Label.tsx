import InputLabel from '@github-ui/input-label'
import type {FC} from 'react'
import type React from 'react'
import {useContext} from 'react'

import styles from './Label.module.css'
import {MarkdownEditorContext} from './MarkdownEditorContext'

type LabelProps = {
  visuallyHidden?: boolean
  children?: React.ReactNode
}

// ref is not forwarded because InputLabel does not (yet) support it
const Legend: FC<LabelProps> = ({...props}) => {
  // using context and definining a Slot in the same component causes an infinite loop, so these must be separate
  const {disabled, required} = useContext(MarkdownEditorContext)

  return <InputLabel as="legend" disabled={disabled} required={required} className={styles.inputLabel} {...props} />
}
Legend.displayName = 'MarkdownEditor.Label'

export const Label: FC<LabelProps> = props => <Legend {...props} />
