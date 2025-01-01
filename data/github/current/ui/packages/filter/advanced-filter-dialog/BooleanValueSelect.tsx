import {testIdProps} from '@github-ui/test-id-props'
import {TriangleDownIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {Octicon} from '@primer/react/deprecated'

import type {MutableFilterBlock} from '../types'
import {getFilterValue} from '../utils'
import styles from './BooleanValueSelect.module.css'
import {ValuePlaceholder} from './ValuePlaceholder'

interface BooleanValueSelectProps {
  filterBlock: MutableFilterBlock
  setFilterValues: (selected: ItemInput | ItemInput[] | boolean | undefined) => void
}

export const BooleanValueSelect = ({filterBlock, setFilterValues}: BooleanValueSelectProps) => {
  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <Button
          size="small"
          className={styles.Button_0}
          trailingVisual={() => <Octicon icon={TriangleDownIcon} className={styles.Octicon_0} />}
          {...testIdProps('afd-row-value-select-boolean-button')}
        >
          <ValuePlaceholder filterBlock={filterBlock} />
        </Button>
      </ActionMenu.Anchor>
      <ActionMenu.Overlay>
        <ActionList selectionVariant="single" {...testIdProps('afd-row-value-select-list')}>
          <ActionList.Item
            onSelect={() => setFilterValues(true)}
            selected={
              getFilterValue(filterBlock.value?.values[0]?.value) === undefined ||
              getFilterValue(filterBlock.value?.values[0]?.value) === 'true'
            }
          >
            True
          </ActionList.Item>
          <ActionList.Item
            onSelect={() => setFilterValues(false)}
            selected={getFilterValue(filterBlock.value?.values[0]?.value) === 'false'}
          >
            False
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )
}
