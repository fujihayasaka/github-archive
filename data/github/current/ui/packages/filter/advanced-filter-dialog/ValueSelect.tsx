import {testIdProps} from '@github-ui/test-id-props'
import {TriangleDownIcon} from '@primer/octicons-react'
import {Button, SelectPanel, TextInput} from '@primer/react'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {type Dispatch, type SetStateAction, useEffect, useMemo, useState} from 'react'

import {FilterOperator, FilterProviderType, type MutableFilterBlock} from '../types'
import {getFilterValue} from '../utils'
import {BooleanValueSelect} from './BooleanValueSelect'
import {ValuePlaceholder} from './ValuePlaceholder'
import styles from './ValueSelect.module.css'

interface ValueSelectProps {
  filterBlock: MutableFilterBlock
  index: number
  selectedFilteredValues: ItemInput | ItemInput[] | undefined
  setValuesFilter: Dispatch<SetStateAction<string>>
  setFilterValues: (selected: ItemInput | ItemInput[] | boolean | undefined) => void
  setFilterFrom: React.ChangeEventHandler<HTMLInputElement> | undefined
  setFilterTo: React.ChangeEventHandler<HTMLInputElement> | undefined
  setFilterText: React.ChangeEventHandler<HTMLInputElement> | undefined
  valueElements: ItemInput[]
}

const selectValueTypeOptions = new Set<FilterProviderType>([FilterProviderType.Select, FilterProviderType.User])
const isSelectValueType = (type?: FilterProviderType) => type && selectValueTypeOptions.has(type)

const isDateValueType = (type?: FilterProviderType) => type && type === FilterProviderType.Date

const inputValueTypeOptions = new Set<FilterProviderType>([
  FilterProviderType.Number,
  FilterProviderType.Date,
  FilterProviderType.Text,
])
const isInputValueType = (type?: FilterProviderType) => type && inputValueTypeOptions.has(type)

export const ValueSelect = ({
  filterBlock,
  setValuesFilter,
  setFilterValues,
  setFilterFrom,
  setFilterText,
  setFilterTo,
  valueElements,
  index,
  selectedFilteredValues,
}: ValueSelectProps) => {
  const [filterValuesOpen, setFilterValuesOpen] = useState(false)

  useEffect(() => {
    if (!filterValuesOpen) {
      // Clear out any active filter when closed
      setValuesFilter('')
    }
  }, [filterValuesOpen, setValuesFilter])

  const selectPanelProps = useMemo(
    () => ({
      renderAnchor: ({...anchorProps}: React.HTMLAttributes<HTMLElement>) => (
        <Button
          {...anchorProps}
          id={`afd-row-${index}-value`}
          size="small"
          alignContent="start"
          disabled={!filterBlock.operator}
          aria-label={`Value ${index + 1}`}
          className={clsx('advanced-filter-item-value', styles.Button_0)}
          trailingVisual={() => <TriangleDownIcon className={styles.Octicon_0} />}
          {...testIdProps('afd-row-value-select-button')}
        >
          <div className={styles.Box_0}>
            <ValuePlaceholder filterBlock={filterBlock} />
          </div>
        </Button>
      ),
      placeholderText: `Filter values`,
      open: filterValuesOpen,
      onOpenChange: setFilterValuesOpen,
      items: valueElements,
      onFilterChange: setValuesFilter,
      showItemDividers: false,
      overlayProps: {width: 'small' as const, className: styles.Overlay},
      ...testIdProps('afd-row-value-select'),
    }),
    [filterValuesOpen, valueElements, setValuesFilter, index, filterBlock],
  )
  if (isSelectValueType(filterBlock.provider?.type)) {
    /**
     * NOTE: While the below looks identical, this has to be broken out so that the typings will deterministically
     * set the props as either a single value or an array
     */
    if (Array.isArray(selectedFilteredValues)) {
      return <SelectPanel {...selectPanelProps} selected={selectedFilteredValues} onSelectedChange={setFilterValues} />
    }
    return <SelectPanel {...selectPanelProps} selected={selectedFilteredValues} onSelectedChange={setFilterValues} />
  }

  if (filterBlock.provider?.type === FilterProviderType.Boolean) {
    return <BooleanValueSelect index={index} filterBlock={filterBlock} setFilterValues={setFilterValues} />
  }

  if (isInputValueType(filterBlock.provider?.type)) {
    if (filterBlock.operator === FilterOperator.Between) {
      return (
        <BetweenFilterInputs
          index={index}
          fromValue={getFilterValue(filterBlock.value?.values[0]?.value) ?? ''}
          toValue={getFilterValue(filterBlock.value?.values[1]?.value) ?? ''}
          setFromValue={setFilterFrom}
          setToValue={setFilterTo}
        />
      )
    }
    const placeholder = isDateValueType(filterBlock.provider?.type)
      ? 'YYYY-MM-DD'
      : `Enter a ${filterBlock.provider?.type.toString().toLowerCase() ?? 'value'}`

    const inputType = filterBlock.provider?.type === FilterProviderType.Number ? 'number' : 'text'
    return (
      <TextInput
        aria-label={`Value ${index + 1}`}
        size="small"
        type={inputType}
        value={filterBlock.value?.raw}
        onChange={setFilterText}
        placeholder={placeholder}
        className={styles.TextInput_0}
        {...testIdProps(`afd-row-${index}`)}
      />
    )
  }
  return (
    <TextInput
      aria-label={`Value ${index + 1}`}
      size="small"
      value={filterBlock.value?.raw}
      onChange={setFilterText}
      placeholder="Enter search text"
      className={styles.TextInput_0}
      {...testIdProps(`afd-row-${index}`)}
    />
  )
}

interface BetweenFilterInputsProps {
  index: number
  fromValue: string
  toValue: string
  setFromValue: React.ChangeEventHandler<HTMLInputElement> | undefined
  setToValue: React.ChangeEventHandler<HTMLInputElement> | undefined
}

const BetweenFilterInputs = ({index, fromValue, toValue, setFromValue, setToValue}: BetweenFilterInputsProps) => (
  <div className={styles.Box_1}>
    <TextInput
      aria-label={`Value ${index + 1} From`}
      size="small"
      value={fromValue}
      onChange={setFromValue}
      placeholder="From"
      className={styles.TextInput_1}
      {...testIdProps(`afd-row-${index}-from`)}
    />
    <span>-</span>
    <TextInput
      aria-label={`Value ${index + 1} To`}
      size="small"
      value={toValue}
      onChange={setToValue}
      placeholder="To"
      className={styles.TextInput_1}
      {...testIdProps(`afd-row-${index}-to`)}
    />
  </div>
)
