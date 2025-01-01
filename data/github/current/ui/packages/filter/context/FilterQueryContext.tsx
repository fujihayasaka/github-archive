import {isFeatureEnabled} from '@github-ui/feature-flags'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {createContext, useCallback, useContext, useEffect, useMemo, useRef, useState} from 'react'

import {FILTER_PRIORITY_DISPLAY_THRESHOLD} from '../constants/filter-constants'
import {FilterQuery} from '../filter-query'
import {FilterQueryParser} from '../parser'
import {HasFilterProvider} from '../providers/has'
import {NoFilterProvider as NoFilterProviderOld, NoFilterProviderV2 as NoFilterProviderNew} from '../providers/no'
import {
  type FilterConfig,
  type FilterProvider,
  type FilterSuggestion,
  FilterValueType,
  type Parser,
  SubmitEvent,
  type ValuePresenceFilterType,
} from '../types'
import {checkFilterQuerySync, promiseTimeout} from '../utils'
import {useFilter} from '.'

interface FilterQueryContext {
  clearFilter: () => void
  filterQuery: FilterQuery
  filterProviders: Record<string, FilterProvider>
  insertIntoQuery: (value: string, caretIndex: number, triggerSubmit?: boolean) => void
  forceReparse: (cursor?: number, callback?: (query: FilterQuery) => void | Promise<void>) => void
  onSubmit: (eventType: SubmitEvent, analyticsName?: string, updatedQuery?: FilterQuery) => void
  rawFilterRef: React.MutableRefObject<string> | null
  replaceActiveBlockWithPresenceBlock: (blockType: ValuePresenceFilterType) => void
  updateFilter: (
    unparsedFilter?: string,
    caret?: number,
    callback?: (query: FilterQuery) => void,
    eventType?: SubmitEvent,
  ) => void
  updateFromExternal: (callback: (query: FilterQuery) => void | Promise<void>) => void
}

export const FilterQueryContext = createContext<FilterQueryContext | undefined>(undefined)

export const useFilterQuery = () => {
  const context = useContext(FilterQueryContext)
  if (!context) {
    throw new Error('useFilterQuery must be used inside a FilterQueryContext')
  }

  return context
}

interface FilterQueryContextProviderProps {
  children: React.ReactNode
  context?: Record<string, string>
  customParser?: Parser<FilterQuery>
  filterConfig: FilterConfig
  providers: FilterProvider[]
  inputRef: React.RefObject<HTMLInputElement>
  onChange: (value: string) => void
  onParse?: (request: FilterQuery) => void
  onSubmit?: (request: FilterQuery, eventType: SubmitEvent) => void
  onValidation: (messages: string[], filterQuery: FilterQuery) => void
  rawFilter: string
}

export const FilterQueryContextProvider = ({
  children,
  context: externalContext,
  customParser,
  filterConfig,
  providers: externalProviders,
  inputRef,
  onChange,
  onParse,
  onSubmit,
  onValidation,
  rawFilter,
}: FilterQueryContextProviderProps) => {
  const latestRawFilterRef = useRef(rawFilter ?? '')
  const parser = useRef(customParser ?? new FilterQueryParser(externalProviders, filterConfig))
  const [filterQuery, setFilterQuery] = useState<FilterQuery>(() =>
    parser.current.parse(rawFilter, new FilterQuery(), -1),
  )
  const [isInitialValidation, setIsInitialValidation] = useState(true)
  const {inputContextRef, config} = useFilter()

  const useUpdatedNoProvider = isFeatureEnabled('issues_advanced_search_has_filter')

  const variant =
    config.variant === 'full' ? 'button_and_input' : config.variant === 'input' ? 'input_only' : 'button_only'

  const {sendClickAnalyticsEvent} = useClickAnalytics()

  useEffect(() => {
    // eslint-disable-next-line react-compiler/react-compiler
    filterQuery.staticContext = externalContext
  }, [externalContext, filterQuery])

  const clearFilter = useCallback(() => {
    onChange('')
    onSubmit?.(new FilterQuery(), SubmitEvent.Clear)
    inputRef.current?.focus()
  }, [inputRef, onChange, onSubmit])

  const filterProviders = useMemo<Record<string, FilterProvider>>(() => {
    const record: Record<string, FilterProvider> = {}
    const noProviders: FilterProvider[] = []
    const hasProviders: FilterProvider[] = []

    externalProviders.map(provider => {
      record[provider.key] = provider
      if (provider.options.filterTypes.valueless) {
        noProviders.push(provider)
      }

      if (provider.options.filterTypes.hasValue) {
        hasProviders.push(provider)
      }
    })

    if (noProviders.length) {
      const NoProviderClass = useUpdatedNoProvider ? NoFilterProviderNew : NoFilterProviderOld

      const presenceProviderValues: FilterSuggestion[] = noProviders
        .sort((a, b) => (a.displayName ?? a.key)?.localeCompare(b.displayName ?? b.key) ?? 0)
        .map(provider => ({
          value: provider.key,
          priority: FILTER_PRIORITY_DISPLAY_THRESHOLD,
          displayName: provider.displayName,
          type: FilterValueType.Value,
          icon: provider.icon,
        }))
      record.no = new NoProviderClass(presenceProviderValues)
    }

    if (hasProviders.length) {
      const presenceProviderValues: FilterSuggestion[] = hasProviders
        .sort((a, b) => (a.displayName ?? a.key)?.localeCompare(b.displayName ?? b.key) ?? 0)
        .map(provider => ({
          value: provider.key,
          priority: FILTER_PRIORITY_DISPLAY_THRESHOLD,
          displayName: provider.displayName,
          type: FilterValueType.Value,
          icon: provider.icon,
        }))
      record.has = new HasFilterProvider(presenceProviderValues)
    }

    parser.current.filterProviders = Object.values(record)
    return record
  }, [externalProviders, useUpdatedNoProvider])

  const postQueryValidate = useCallback(
    (request: FilterQuery, showAllErrors = false) => {
      onValidation(
        request.getErrors(showAllErrors || document.activeElement !== inputRef.current),
        new FilterQuery(request.raw, request.blocks, filterConfig, request.activeBlock),
      )
    },
    [filterConfig, inputRef, onValidation],
  )

  const parseAndValidate = useCallback(
    (caret: number, callback?: (query: FilterQuery) => void, newRaw?: string) => {
      setIsInitialValidation(false)
      new Promise<FilterQuery>((resolve, reject) => {
        const query = parser.current.parse(newRaw ?? rawFilter, filterQuery, caret)
        if (checkFilterQuerySync(query, latestRawFilterRef.current)) {
          setFilterQuery(query)
          resolve(query)
        } else {
          reject(new Error('Query out of sync, Aborted...'))
        }
      })
        // * While we do want to use async/await, in this case it actually results in a broken experience as it blocks
        // * the UI from updating
        // eslint-disable-next-line github/no-then
        .then((query: FilterQuery) => parser.current.validateFilterQuery(query))
        // eslint-disable-next-line github/no-then
        .then((newQuery: FilterQuery) => {
          return new Promise<FilterQuery>((resolve, reject) => {
            if (newQuery && checkFilterQuerySync(newQuery)) {
              setFilterQuery(newQuery)
              return resolve(newQuery)
            }
            return reject(new Error(newQuery ? 'Out of sync' : 'Empty Query, Aborted...'))
          })
        })
        // eslint-disable-next-line github/no-then
        .then((query: FilterQuery) => {
          callback?.(query)
        })
        // eslint-disable-next-line github/no-then
        .catch(() => {})
    },
    [filterQuery, rawFilter],
  )

  const forceReparse = useCallback(
    (cursorLocation?: number, callback?: (query: FilterQuery) => void) => {
      const caret = cursorLocation ? cursorLocation : inputContextRef.current?.caretStart ?? -1
      parseAndValidate(caret, query => {
        postQueryValidate(query)
        callback?.(query)
      })
    },
    [inputContextRef, parseAndValidate, postQueryValidate],
  )

  const onSubmitHandler = useCallback(
    async (eventType: SubmitEvent, analyticsName?: string, updatedQuery?: FilterQuery) => {
      const query = updatedQuery ?? filterQuery

      // Clearing the active block so validation errors will show
      query.clearActiveBlock()

      let retry = 0
      let hasSubmitted = false
      while (retry <= 3) {
        if (checkFilterQuerySync(query, rawFilter)) {
          onSubmit?.(query, eventType)
          postQueryValidate(query, true)
          hasSubmitted = true
          break
        } else {
          retry += 1
          await promiseTimeout(10)
        }
      }

      if (!hasSubmitted) {
        //Final attempt
        parseAndValidate(inputContextRef.current?.caretStart ?? -1, q => {
          if (checkFilterQuerySync(q, rawFilter)) {
            onSubmit?.(q, eventType)
            postQueryValidate(query, true)
          }
        })
      }

      const filtersUsed = filterQuery.filtersUsed.length > 0 ? filterQuery.filtersUsed.join(',') : ''

      sendClickAnalyticsEvent({
        action: 'submit_filter_query',
        label: `variant:${variant};event_type:${eventType};used_filter_providers:${filtersUsed};nested_group_depth:${
          filterQuery.nestedGroupCount
        };submitted_by:${analyticsName ?? 'unnamed_submit_method'}`,
      })
    },
    [
      filterQuery,
      inputContextRef,
      onSubmit,
      parseAndValidate,
      postQueryValidate,
      rawFilter,
      sendClickAnalyticsEvent,
      variant,
    ],
  )

  const updateFilter = useCallback(
    (
      unparsedFilter?: string,
      caret: number = -1,
      callback?: (query: FilterQuery) => void | null,
      eventType?: SubmitEvent,
    ) => {
      const updatedRaw = unparsedFilter ?? filterQuery.raw

      onChange?.(updatedRaw)
      if (eventType) {
        latestRawFilterRef.current = updatedRaw
        parseAndValidate(
          caret,
          query => {
            if (checkFilterQuerySync(query, latestRawFilterRef.current)) {
              callback?.(query)
              onSubmit?.(query, eventType)
            }
          },
          updatedRaw,
        )
      }
    },
    [filterQuery.raw, onChange, onSubmit, parseAndValidate],
  )

  const replaceActiveBlockWithPresenceBlock = useCallback(
    (type: ValuePresenceFilterType) => {
      const [raw, cursorIndex] = parser.current.replaceActiveBlockWithPresenceBlock(filterQuery, type)
      inputContextRef.current?.updateCaretPosition(cursorIndex)
      updateFilter(raw, cursorIndex)
    },
    [filterQuery, inputContextRef, updateFilter],
  )

  const insertIntoQuery = useCallback(
    (value: string, caretIndex: number, triggerSubmit: boolean = false) => {
      const [raw, cursorIndex] = parser.current.insertSuggestion(filterQuery, value, caretIndex)
      inputContextRef.current?.updateCaretPosition(cursorIndex)
      // Insert the updated raw query into the input context
      inputContextRef.current?.updateRawFilterValue(raw)
      updateFilter(raw, cursorIndex, undefined, triggerSubmit ? SubmitEvent.SuggestionSelected : undefined)
    },
    [filterQuery, inputContextRef, updateFilter],
  )

  const updateFromExternal = useCallback(
    (callback: (query: FilterQuery) => void) => {
      if (rawFilter !== latestRawFilterRef.current || isInitialValidation) {
        latestRawFilterRef.current = rawFilter
        parseAndValidate(inputContextRef.current?.caretStart ?? -1, query => {
          postQueryValidate(query)
          onParse?.(query)
          callback(query)
        })
      }
    },
    [inputContextRef, isInitialValidation, onParse, parseAndValidate, postQueryValidate, rawFilter],
  )

  const filterQueryContextValue: FilterQueryContext = useMemo(
    () => ({
      clearFilter,
      filterQuery,
      filterProviders,
      forceReparse,
      insertIntoQuery,
      onSubmit: onSubmitHandler,
      rawFilterRef: latestRawFilterRef,
      replaceActiveBlockWithPresenceBlock,
      updateFilter,
      updateFromExternal,
    }),
    [
      clearFilter,
      filterProviders,
      filterQuery,
      forceReparse,
      insertIntoQuery,
      onSubmitHandler,
      replaceActiveBlockWithPresenceBlock,
      updateFilter,
      updateFromExternal,
    ],
  )

  return <FilterQueryContext.Provider value={filterQueryContextValue}>{children}</FilterQueryContext.Provider>
}
