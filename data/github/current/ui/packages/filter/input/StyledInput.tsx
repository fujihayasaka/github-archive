import {clsx} from 'clsx'
import {type ReactNode, useEffect, useMemo, useRef} from 'react'

import {DYNAMIC_VALUE_CHARS} from '../constants/filter-constants'
import {useFilter, useFilterQuery, useInput} from '../context'
import {type AnyBlock, BlockType, type BlockValueItem, type FilterBlock, FilterOperator} from '../types'
import {checkFilterQuerySync, getFilterValue, isFilterBlock, isIndexedGroupBlock} from '../utils'
import styles0 from './StyledInput.module.css'
import {Delimiter, KeyBlock, KeywordBlock, SpaceBlock, TextBlock} from './StyledInputBlocks'

const OneCharModifiers = [
  FilterOperator.GreaterThan,
  FilterOperator.LessThan,
  FilterOperator.Before,
  FilterOperator.After,
]

const TwoCharModifiers = [
  FilterOperator.GreaterThanOrEqualTo,
  FilterOperator.LessThanOrEqualTo,
  FilterOperator.BeforeAndIncluding,
  FilterOperator.AfterAndIncluding,
]

export const StyledInput = () => {
  const {config} = useFilter()
  const {inputFocused, updateStyledInputBlockCount} = useInput()
  const {rawFilterRef, filterQuery, isInitialValidation} = useFilterQuery()
  const cachedNodes = useRef<ReactNode[]>([])

  const getValueElement = (element: FilterBlock, blockValue: BlockValueItem, index: number, position?: number) => {
    const {id, key, operator} = element
    const {value, valid} = blockValue
    if (!isInitialValidation) {
      if (valid) {
        let dynamicPosition = 0
        if (OneCharModifiers.includes(operator)) {
          dynamicPosition = 1
        } else if (TwoCharModifiers.includes(operator)) {
          dynamicPosition = 2
        }

        const dynamicValueChar = getFilterValue(value)?.charAt(dynamicPosition)
        if (dynamicValueChar && DYNAMIC_VALUE_CHARS.includes(dynamicValueChar)) {
          return (
            <span
              key={`filter-block-${index}-${key.value}-${position ? `${position}-` : ''}${getFilterValue(value)}`}
              data-type="filter-value"
              className={clsx(valid ? `valid-filter-value` : `invalid-filter-value`, styles0.Box_0)}
            >
              {getFilterValue(value)}
            </span>
          )
        } else {
          return (
            <span
              key={`filter-block-${index}-${key.value}-${position ? `${position}-` : ''}${getFilterValue(value)}`}
              data-type="filter-value"
              className={clsx(valid ? `valid-filter-value` : `invalid-filter-value`, styles0.Box_1)}
            >
              {getFilterValue(value)}
            </span>
          )
        }
      } else if (
        valid !== undefined &&
        ((valid === false && (filterQuery.activeBlock as FilterBlock)?.id !== id) || !inputFocused)
      ) {
        return (
          <span
            key={`filter-block-${index}-${key.value}-${position ? `${position}-` : ''}${getFilterValue(value)}`}
            data-type="filter-value"
            className={clsx(valid ? `valid-filter-value` : `invalid-filter-value`, styles0.Box_2)}
          >
            {getFilterValue(value)}
          </span>
        )
      }
    }

    return (
      <span
        key={`filter-block-${index}-${key.value}-${position ? `${position}-` : ''}${getFilterValue(value)}`}
        data-type="filter-value"
        className={valid ? `valid-filter-value` : `invalid-filter-value`}
      >
        {getFilterValue(value)}
      </span>
    )
  }

  const styledInput = useMemo(() => {
    const inputParts: ReactNode[] = []

    if (!checkFilterQuerySync(filterQuery, rawFilterRef?.current)) {
      return cachedNodes.current
    }

    function getStyledInputs(subBlocks: AnyBlock[], parentKey: string) {
      for (const [index, element] of subBlocks.entries()) {
        let queryItem: ReactNode

        if (isFilterBlock(element)) {
          const {key, operator, value} = element

          const isInvalidFilterValue =
            key.valid === false && ((filterQuery.activeBlock as FilterBlock)?.id !== element.id || !inputFocused)

          const filterKey = (
            <KeyBlock
              key={`filter-block-${index}-key`}
              text={key.value}
              className={clsx(isInvalidFilterValue && styles0.KeyBlock_0)}
            />
          )
          const filterDelimiter = (
            <Delimiter key={`filter-block-${index}-delimiter`} delimiter={config.filterDelimiter} />
          )

          let filterValues: JSX.Element[] = []

          if (operator === FilterOperator.Between) {
            const value1 = value.values[0]
            const value2 = value.values[1]
            if (value1) {
              filterValues.push(getValueElement(element, value1, index, 1))
            }
            filterValues.push(
              <span key={`filter-block-${index}-${key.value}-delimiter-1`} className={`delimiter`}>
                ..
              </span>,
            )
            if (value2) {
              filterValues.push(getValueElement(element, value2, index, 2))
            }
          } else {
            filterValues = value.values.map((v, i) => {
              return (
                // eslint-disable-next-line @eslint-react/no-array-index-key
                <span key={`filter-block-${index}-${key.value}-values-${i}}`}>
                  {i > 0 && (
                    // eslint-disable-next-line @eslint-react/no-array-index-key
                    <span key={`filter-block-${index}-${key.value}-delimiter-${i}`} className={`delimiter`}>
                      {config.valueDelimiter}
                    </span>
                  )}
                  {getValueElement(element, v, index)}
                </span>
              )
            })
          }

          queryItem = (
            <span key={`filter-block-${parentKey}-${index}-${key.value}`} data-type="filter-expression">
              {filterKey}
              {filterDelimiter}
              {filterValues}
              {/* Adds the trailing space as a separate element so it isn't included in the styling for the filter value */}
            </span>
          )
        } else if (element.type === BlockType.Space) {
          queryItem = <SpaceBlock key={`space-block-${parentKey}-${index}`} text={element.raw} />
        } else if (element.type === BlockType.Keyword) {
          queryItem = <KeywordBlock key={`keyword-block-${parentKey}-${index}`} keyword={element.raw} />
        } else if (isIndexedGroupBlock(element)) {
          inputParts.push(<TextBlock key={`text-open-${parentKey}-${index}`} text={'('} />)
          getStyledInputs(element.blocks, parentKey ? `${parentKey}-${index}` : `${index}`)
          inputParts.push(<TextBlock key={`text-close-${parentKey}-${index}`} text={')'} />)
        } else {
          queryItem = <TextBlock key={`text-block-${parentKey}-${index}`} text={element.raw} />
        }

        inputParts.push(queryItem)
      }
    }

    getStyledInputs(filterQuery.blocks, 'root')

    cachedNodes.current = inputParts
    return inputParts
    // Linter won't allow this to subscribe to sub properties of filterQuery
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    filterQuery.raw,
    filterQuery.blocks,
    filterQuery.activeBlock,
    filterQuery.isValidated,
    inputFocused,
    config.filterDelimiter,
    config.valueDelimiter,
  ])

  useEffect(() => {
    updateStyledInputBlockCount(styledInput.length)
  }, [styledInput.length, updateStyledInputBlockCount])

  return <>{styledInput.length === 0 ? rawFilterRef?.current : styledInput}</>
}
