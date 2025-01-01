import {testIdProps} from '@github-ui/test-id-props'
import type {ActionListItemInput as ItemInput} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {hasMatch} from 'fzy.js'
import {useCallback, useEffect, useMemo, useState} from 'react'

import {ValueOperators} from '../constants/filter-constants'
import {useFilter, useFilterQuery} from '../context'
import {RawTextProvider} from '../providers/raw'
import {
  type BlockValue,
  type FilterBlock,
  type FilterOperator,
  type FilterProvider,
  FilterProviderType,
  type FilterValueData,
  FilterValueType,
  type MutableFilterBlock,
} from '../types'
import {
  capitalize,
  getAllFilterOperators,
  getFilterValue,
  getUnescapedFilterValue,
  isMutableFilterBlock,
} from '../utils'
import styles from './AdvancedFilterItem.module.css'
import {OperatorSelect} from './OperatorSelect'
import {QualifierSelect} from './QualifierSelect'
import {RemoveFilterButton} from './RemoveFilterButton'
import {ValueSelect} from './ValueSelect'

interface AdvancedFilterItemProps {
  index: number
  filterBlock: MutableFilterBlock | FilterBlock
  filterProviders: FilterProvider[]
  updateFilterBlock: (filterBlock: MutableFilterBlock) => void
  deleteFilterBlock: (index: number) => void
}

export const AdvancedFilterItem = ({
  index,
  filterBlock,
  filterProviders,
  updateFilterBlock,
  deleteFilterBlock,
}: AdvancedFilterItemProps) => {
  const {config} = useFilter()
  const {filterQuery} = useFilterQuery()
  const [values, setValues] = useState<FilterValueData[]>(filterBlock.provider?.filterValues ?? [])
  const [valuesFilter, setValuesFilter] = useState('')
  const [selectedFilteredValues, setSelectedFilteredValues] = useState<ItemInput | ItemInput[] | undefined>(
    filterBlock.provider?.options?.filterTypes.multiValue ? [] : undefined,
  )
  const filteredValues = useMemo(() => {
    if (!isMutableFilterBlock(filterBlock)) return []
    const vals = values.filter(value =>
      valuesFilter.length > 0
        ? hasMatch(valuesFilter, getFilterValue(value.value) ?? '') || hasMatch(valuesFilter, value.displayName ?? '')
        : true,
    )
    return vals
  }, [filterBlock, valuesFilter, values])

  const amendedFilterProviders: FilterProvider[] = useMemo(() => {
    const providers = Array.from(filterProviders)
    if (filterBlock.provider && !filterProviders.find(p => p.key === filterBlock.provider?.key))
      providers.push(filterBlock.provider)
    return providers.sort((a, b) => (a.displayName ?? a.key)?.localeCompare(b.displayName ?? b.key) ?? 0)
  }, [filterBlock.provider, filterProviders])

  const valueElements: ItemInput[] = useMemo(() => {
    // Append selected items to top of the list of elements
    const initialValueElements = Array.isArray(selectedFilteredValues)
      ? [...selectedFilteredValues]
      : selectedFilteredValues
        ? [selectedFilteredValues]
        : []
    return filteredValues?.reduce((elements, value) => {
      const row = filterBlock.provider?.getValueRowProps(value)
      const foundIndex = elements.findIndex(v => v.text === row?.text) ?? -1
      if (foundIndex === -1) {
        elements.push({
          ...row,
          leadingVisual: row?.leadingVisual ? () => row.leadingVisual! : undefined,
          trailingVisual: row?.trailingVisual ? () => row.trailingVisual! : undefined,
        })
      }
      return elements
    }, initialValueElements)
  }, [filterBlock.provider, filteredValues, selectedFilteredValues])

  const setFilterProvider = useCallback(
    (provider: FilterProvider) => {
      if (provider.type !== FilterProviderType.RawText) {
        const isRawTextToText =
          filterBlock.provider?.type === FilterProviderType.RawText && provider.type === FilterProviderType.Text
        const newValue =
          provider.type === filterBlock.provider?.type || isRawTextToText ? filterBlock.value : {raw: '', values: []}

        updateFilterBlock({
          ...filterBlock,
          key: {value: provider.key, valid: true},
          provider,
          operator: getAllFilterOperators(provider)[0],
          value: newValue,
        })
      } else {
        const newValue =
          filterBlock.provider?.type === FilterProviderType.Text && filterBlock.value
            ? filterBlock.value
            : {raw: '', values: []}

        updateFilterBlock({
          ...filterBlock,
          key: undefined,
          provider: RawTextProvider,
          operator: getAllFilterOperators(RawTextProvider)[0],
          raw: newValue.raw,
          value: newValue,
        })
      }
    },
    [filterBlock, updateFilterBlock],
  )

  const setFilterOperator = useCallback(
    (operator: FilterOperator) => {
      let valueObj: {value?: BlockValue} = {}

      // We only care if we are changing operators when in a FilterBlock, which would mean it has values
      if (filterBlock.value && !ValueOperators.includes(operator)) {
        const updatedRaw: string[] = []
        const updatedValues =
          filterBlock.value.values.map(v => {
            const newValue =
              getUnescapedFilterValue(v.value)
                ?.replace(/^[<>]=?/g, '')
                .replaceAll('..', '') ?? ''
            updatedRaw.push(newValue)
            return {...v, value: newValue}
          }) ?? []
        valueObj = {
          value: {
            values: updatedValues,
            raw: updatedRaw.join(config.valueDelimiter),
          },
        }
      }

      updateFilterBlock({...filterBlock, operator, ...valueObj})
    },
    [config.valueDelimiter, filterBlock, updateFilterBlock],
  )

  const setFilterValues = useCallback(
    (selected: ItemInput | ItemInput[] | boolean | undefined) => {
      let newValues: FilterValueData[] = []
      if (selected === undefined) {
        newValues = []
      } else if (typeof selected === 'boolean') {
        newValues = [{value: selected.toString(), displayName: capitalize(selected.toString())}]
      } else if (!filterBlock.provider?.options?.filterTypes.multiValue || !Array.isArray(selected)) {
        const itemValue = (selected as ItemInput).text
        const value = values.find(v => v.displayName === itemValue || v.value === itemValue)
        if (value === undefined) return
        newValues = [value]
      } else {
        // First, we invert the filter on the selected items (i.e. any item that doesn't match the filter)
        const invisibleSelections = filterBlock.value?.values.filter(
          v => !hasMatch(valuesFilter, getFilterValue(v.value) ?? '') && !hasMatch(valuesFilter, v.displayName ?? ''),
        )
        // Take the filtered out selections and initialize the new values with them
        if (invisibleSelections) newValues = invisibleSelections

        for (const selectedItem of selected) {
          const foundValue = values.find(v => v.displayName === selectedItem.text || v.value === selectedItem.text)
          if (foundValue) newValues.push(foundValue)
        }
      }

      // Filtering out any empty values
      newValues = newValues.filter(v => v.value.length > 0)

      setSelectedFilteredValues(typeof selected === 'boolean' ? undefined : selected)
      updateFilterBlock({
        ...filterBlock,
        value: {
          ...filterBlock.value,
          raw: newValues.map(v => getFilterValue(v.value)).join(config.valueDelimiter),
          values: newValues.map(v => ({...v, valid: true})),
        },
      })
    },
    [config.valueDelimiter, filterBlock, updateFilterBlock, values, valuesFilter],
  )

  const setFilterFrom: React.ChangeEventHandler<HTMLInputElement> = useCallback(
    e => {
      const blockValues = [
        {value: e.target.value, valid: true},
        filterBlock.value?.values?.[1] ?? {value: '', valid: true},
      ]
      const raw = `${getFilterValue(blockValues[0]?.value)}..${getFilterValue(blockValues[1]?.value)}`
      updateFilterBlock({
        ...filterBlock,
        value: {
          values: blockValues,
          raw,
        },
      })
    },
    [filterBlock, updateFilterBlock],
  )

  const setFilterTo: React.ChangeEventHandler<HTMLInputElement> = useCallback(
    e => {
      const blockValues = [
        filterBlock.value?.values?.[0] ?? {value: '', valid: true},
        {value: e.target.value, valid: true},
      ]
      const raw = `${getFilterValue(blockValues[0]?.value)}..${getFilterValue(blockValues[1]?.value)}`
      updateFilterBlock({
        ...filterBlock,
        value: {
          values: blockValues,
          raw,
        },
      })
    },
    [filterBlock, updateFilterBlock],
  )

  const setFilterText: React.ChangeEventHandler<HTMLInputElement> = useCallback(
    e => {
      updateFilterBlock({...filterBlock, value: {values: [{value: e.target.value, valid: true}], raw: e.target.value}})
    },
    [filterBlock, updateFilterBlock],
  )

  useEffect(() => {
    const getSuggestions = async () => {
      // TODO: This will be fixed by https://github.com/github/collaboration-workflows-flex/issues/909
      if (filterBlock.provider) {
        const suggestions = await filterBlock.provider.getSuggestions(
          filterQuery,
          {
            ...filterBlock,
            value: {values: [{value: valuesFilter, valid: true}], raw: valuesFilter},
          },
          config,
        )
        setValues(
          suggestions
            ? suggestions.filter(
                suggestion =>
                  suggestion.type !== FilterValueType.NoValue && !suggestion.displayName?.startsWith('Exclude'),
              )
            : [],
        )
      }
    }
    void getSuggestions()
  }, [config, filterBlock, filterBlock.provider, filterQuery, valuesFilter])

  return (
    <>
      <fieldset className={clsx(`advanced-filter-item-${index}`, styles.Box_0)} {...testIdProps('afd-filter-row')}>
        <legend className={styles.Box_1}>
          <h2>{`Row ${index + 1}`}</h2>
        </legend>
        <span className={styles.Text_0}>{index + 1}</span>
        <div className={styles.Box_2}>
          <div className={styles.Box_3}>
            <div className={styles.Box_4}>
              <span className={styles.Text_1}>Qualifier</span>
              <QualifierSelect
                filterBlock={filterBlock}
                index={index}
                filterProviders={amendedFilterProviders}
                setFilterProvider={setFilterProvider}
              />
            </div>
            <div className={styles.Box_4}>
              <span className={styles.Text_1}>Operator</span>
              <OperatorSelect setFilterOperator={setFilterOperator} filterBlock={filterBlock} index={index} />
            </div>
            <div className={styles.Box_4}>
              <span className={styles.Text_1}>Value</span>
              <ValueSelect
                filterBlock={filterBlock}
                index={index}
                setValuesFilter={setValuesFilter}
                valueElements={valueElements}
                selectedFilteredValues={selectedFilteredValues}
                setFilterValues={setFilterValues}
                setFilterFrom={setFilterFrom}
                setFilterText={setFilterText}
                setFilterTo={setFilterTo}
              />
            </div>
            <RemoveFilterButton
              onClick={() => deleteFilterBlock(index)}
              ariaLabel={`Delete filter ${index + 1}: ${
                filterBlock.provider?.displayName ?? filterBlock.provider?.key
              }, ${filterBlock.operator}, ${filterBlock.value?.raw}`}
              testId={`afd-filter-row-delete-${index}`}
              className={styles.RemoveFilterButton_0}
            />
          </div>
          <div className={styles.Box_5}>
            <div>
              <RemoveFilterButton
                onClick={() => deleteFilterBlock(index)}
                ariaLabel={`Delete filter ${index + 1}: ${
                  filterBlock.provider?.displayName ?? filterBlock.provider?.key
                }, ${filterBlock.operator}, ${filterBlock.value?.raw}`}
              />
            </div>
            <div className={styles.Box_6}>{index + 1}</div>
          </div>
        </div>
      </fieldset>
      <div className={styles.Box_7}>
        <div className={styles.Box_8} />
      </div>
    </>
  )
}
