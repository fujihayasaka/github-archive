import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'

import {FilterOperators} from '../constants/filter-constants'
import {FilterOperator, type MutableFilterBlock} from '../types'
import {getAllFilterOperators} from '../utils'
import styles from './OperatorSelect.module.css'

interface OperatorSelectProps {
  filterBlock: MutableFilterBlock
  index: number
  setFilterOperator: (operator: FilterOperator) => void
}

export const OperatorSelect = ({filterBlock, index, setFilterOperator}: OperatorSelectProps) => {
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <Button
          size="small"
          disabled={!filterBlock.provider}
          id={`afd-row-${index}-operator`}
          aria-label={`Operator ${index + 1}`}
          className={styles.Button_0}
          trailingVisual={() => <Octicon icon={TriangleDownIcon} className={styles.Octicon_0} />}
        >
          {filterBlock.operator ? FilterOperators[filterBlock.operator] : FilterOperators[FilterOperator.Is]}
        </Button>
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="auto">
        <ActionList selectionVariant="single">
          {getAllFilterOperators(filterBlock.provider).map(operator => (
            <ActionList.Item
              key={`advanced-filter-item-${filterBlock.id}-operator-${operator}`}
              onSelect={() => setFilterOperator(operator)}
              selected={operator === filterBlock.operator}
            >
              {FilterOperators[operator]}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
