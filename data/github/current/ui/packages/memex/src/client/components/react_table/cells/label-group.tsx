import type {Label} from '../../../api/common-contracts'
import {LabelToken} from '../../fields/label-token'
import {DropdownCell} from './dropdown-cell'
import styles from './label-group.module.css'

interface LabelGroupProps {
  labels: Array<Label> | undefined
  dropdownRef?: React.MutableRefObject<HTMLButtonElement | null>
  isDisabled?: boolean
}

export const LabelGroup: React.FC<LabelGroupProps> = ({labels, dropdownRef, isDisabled}) => {
  return (
    <DropdownCell ref={dropdownRef} isDisabled={isDisabled}>
      <div className={styles.Box}>{labels?.map(label => <LabelToken key={label.id} label={label} />)}</div>
    </DropdownCell>
  )
}
