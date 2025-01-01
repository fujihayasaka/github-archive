import {testIdProps} from '@github-ui/test-id-props'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {FilterIcon} from '@primer/octicons-react'
import {Button, type ResponsiveValue, useConfirm, useResponsiveValue} from '@primer/react'
import {Dialog} from '@primer/react/experimental'
import {clsx} from 'clsx'
import memoize from 'lodash-es/memoize'
import {type RefObject, useCallback, useMemo, useReducer, useRef, useState} from 'react'

import {Strings} from '../constants/strings'
import {useFilter, useFilterQuery, useSuggestions} from '../context'
import type {FilterQuery} from '../filter-query'
import {RawTextProvider} from '../providers/raw'
import {
  BlockType,
  type FilterButtonVariant,
  type FilterConfig,
  type FilterProvider,
  type MutableFilterBlock,
  ProviderSupportStatus,
  SubmitEvent,
} from '../types'
import {
  buildRawBlockString,
  getAllFilterOperators,
  getBlockKey,
  getMutableFilterBlocks,
  isMutableFilterBlock,
} from '../utils'
import {AddFilterButton} from './AddFilterButton'
import styles from './AdvancedFilterDialog.module.css'
import {BlankState} from './BlankState'
import {FilterList} from './FilterList'

interface AdvancedFilterDialogProps {
  filterButtonVariant?: FilterButtonVariant
  isStandalone?: boolean

  dialogOpen: boolean
  setDialogOpen: (open: boolean) => void
}

const renumberBlocks = (blocks: MutableFilterBlock[]) => {
  return blocks.map((b, i) => ({...b, id: i}))
}

const getWithUpdatedRawValues = memoize((config: FilterConfig) => {
  return (
    _current: MutableFilterBlock[],
    // allow updating with objects that don't have the `raw` field
    updated: Array<Omit<MutableFilterBlock, 'raw'> & {raw?: string}>,
  ) =>
    updated.map((block): MutableFilterBlock => {
      const raw = buildRawBlockString(block, config)
      // avoid creating new object instance unless we have to
      // TS isn't smart enough to see that if `block.raw === raw`, `block.raw` must not be undefined
      return block.raw === raw ? (block as MutableFilterBlock) : {...block, raw}
    })
})

export const AdvancedFilterDialog = ({
  filterButtonVariant = 'normal',
  isStandalone = false,
  dialogOpen,
  setDialogOpen,
}: AdvancedFilterDialogProps) => {
  const {config} = useFilter()
  const {filterQuery, filterProviders, updateFilter} = useFilterQuery()
  const {hideSuggestions} = useSuggestions()
  const buttonRef = useRef<HTMLButtonElement>(null)
  const {sendClickAnalyticsEvent} = useClickAnalytics()

  const addFilterButtonRef = useRef<HTMLButtonElement>(null)
  const addFilterButtonMobileRef = useRef<HTMLButtonElement>(null)
  const addFilterButtonMobileLastRowRef = useRef<HTMLButtonElement>(null)
  const isNarrowBreakpoint = useResponsiveValue<ResponsiveValue<boolean>, false>({regular: false, narrow: true}, false)

  const amendedFilterBlocks: MutableFilterBlock[] = getMutableFilterBlocks(filterQuery.blocks)
  const withUpdatedRawValues = getWithUpdatedRawValues(config)
  // using a reducer we can ensure that the `raw` values always correspond to the rest of the block
  const [filterBlocks, setFilterBlocks] = useReducer(withUpdatedRawValues, amendedFilterBlocks)

  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false)

  const confirm = useConfirm()

  const confirmUnsavedChanges = useCallback(
    async () =>
      !hasUnsavedChanges ||
      (await confirm({...Strings.advancedFilterDialogCloseConfirmation, confirmButtonType: 'danger'})),
    [confirm, hasUnsavedChanges],
  )

  const amendedFilterProviders: FilterProvider[] = useMemo(() => {
    const filteredProviders = Object.values(filterProviders).filter(
      provider =>
        (provider.options.filterTypes.multiKey ||
          filterBlocks.filter(block => isMutableFilterBlock(block) && block.provider?.key === provider.key).length <
            1) &&
        provider.options.support.status === ProviderSupportStatus.Supported,
    )
    if (!(config.disableAdvancedTextFilter && config.variant === 'button')) {
      filteredProviders.push(RawTextProvider)
    }

    return filteredProviders.sort((a, b) => a.key?.localeCompare(b.displayName ?? '') ?? 0)
  }, [config.disableAdvancedTextFilter, config.variant, filterBlocks, filterProviders])

  const resetFilterBlocks = useCallback(() => {
    setFilterBlocks(amendedFilterBlocks)
    setHasUnsavedChanges(false)
  }, [amendedFilterBlocks])

  const addNewFilterBlock = useCallback(
    (provider: FilterProvider) => {
      setFilterBlocks([
        ...filterBlocks,
        {
          id: filterBlocks.length,
          type: BlockType.Filter,
          provider,
          key: getBlockKey(provider),
          operator: getAllFilterOperators(provider)[0],
          value: {raw: '', values: [{value: '', valid: true}]},
        },
      ])
      setHasUnsavedChanges(true)
      setTimeout(() => {
        const lastItem = document.querySelectorAll<HTMLButtonElement>(`.advanced-filter-item-qualifier`)
        lastItem[lastItem.length - 1]?.focus()
      }, 10)
    },
    [filterBlocks],
  )

  const updateFilterBlock = useCallback(
    (filterBlock: MutableFilterBlock) => {
      setHasUnsavedChanges(true)

      const updatedBlocks = filterBlocks.map(block => (block.id === filterBlock.id ? filterBlock : block))
      setFilterBlocks(updatedBlocks)
    },
    [filterBlocks],
  )

  const deleteFilterBlock = useCallback(
    (index: number) => {
      const newFilterBlocks = filterBlocks.filter((_, i) => i !== index)
      setFilterBlocks(renumberBlocks(newFilterBlocks))
      let focusingRef: RefObject<HTMLButtonElement>

      if (isNarrowBreakpoint) {
        focusingRef = newFilterBlocks.length > 0 ? addFilterButtonMobileLastRowRef : addFilterButtonMobileRef
      } else {
        focusingRef = addFilterButtonRef
      }

      setTimeout(() => focusingRef.current?.focus(), 20)
    },
    [filterBlocks, isNarrowBreakpoint],
  )

  const variant = isStandalone ? 'button_only' : 'button_and_input'

  const openDialog = useCallback(() => {
    resetFilterBlocks()
    hideSuggestions()
    setDialogOpen(true)
    sendClickAnalyticsEvent({
      action: 'open_advanced_filter_dialog',
      label: `variant:${variant}`,
    })
  }, [hideSuggestions, resetFilterBlocks, setDialogOpen, sendClickAnalyticsEvent, variant])

  const closeDialog = useCallback(
    async (skipConfirmation?: boolean) => {
      if (!skipConfirmation && !(await confirmUnsavedChanges())) return
      setDialogOpen(false)
      resetFilterBlocks()
      // Timeout needed to set focus on the next tick update. Requires at least 10ms for Safari to work.
      setTimeout(() => {
        buttonRef.current?.focus()
      }, 20)
    },
    [confirmUnsavedChanges, setDialogOpen, resetFilterBlocks],
  )

  const sendApplyAnalyticsEvent = useCallback(
    (query: FilterQuery) => {
      const filtersUsed = query.filtersUsed.length > 0 ? query.filtersUsed.join(',') : ''
      sendClickAnalyticsEvent({
        action: 'submit_filter_query',
        label: `variant:${variant};event_type:${SubmitEvent.DialogSubmit};used_filter_providers:${filtersUsed};nested_group_depth:${query.nestedGroupCount};submitted_by:filter_dialog`,
      })
    },
    [sendClickAnalyticsEvent, variant],
  )

  const applyFilterBlocks = useCallback(async () => {
    const unparsedFilter = filterBlocks.map(({raw}) => raw).join(' ')
    updateFilter(unparsedFilter, unparsedFilter.length, sendApplyAnalyticsEvent, SubmitEvent.DialogSubmit)
    await closeDialog(true)
  }, [closeDialog, filterBlocks, sendApplyAnalyticsEvent, updateFilter])

  return (
    <>
      <Button
        ref={buttonRef}
        onClick={openDialog}
        {...testIdProps('advanced-filter-button')}
        aria-label="Advanced filter dialog"
        leadingVisual={FilterIcon}
        count={filterQuery.filterCount > 0 ? filterQuery.filterCount : undefined}
        className={clsx(styles.Button_0, isStandalone && styles.standaloneButton)}
      >
        {filterButtonVariant === 'normal' && 'Filter'}
      </Button>
      {dialogOpen && (
        <Dialog
          onClose={() => closeDialog()}
          role="dialog"
          title="Advanced filters"
          position={{narrow: 'fullscreen', regular: 'center'}}
          renderFooter={() => (
            <div className={styles.Box_0}>
              <div className={styles.Box_1}>
                <AddFilterButton
                  size={isNarrowBreakpoint ? 'medium' : 'small'}
                  ref={addFilterButtonRef}
                  filterProviders={amendedFilterProviders}
                  addNewFilterBlock={addNewFilterBlock}
                />
              </div>
              <div className={styles.Box_2}>
                <Button
                  size={isNarrowBreakpoint ? 'medium' : 'small'}
                  onClick={() => closeDialog()}
                  {...testIdProps('afd-cancel')}
                >
                  Cancel
                </Button>
                <Button
                  size={isNarrowBreakpoint ? 'medium' : 'small'}
                  variant="primary"
                  onClick={applyFilterBlocks}
                  {...testIdProps('afd-apply')}
                >
                  Apply
                </Button>
              </div>
            </div>
          )}
          renderBody={() => (
            <div
              className={clsx('advanced-filter-dialog-content', styles.Box_4, filterBlocks.length && styles.nonEmpty)}
              {...testIdProps('advanced-filter-dialog-content')}
            >
              <div id="__primerPortalRoot__" style={{zIndex: 10, position: 'absolute', width: '100%'}} />
              <div className={styles.Box_3}>
                {filterBlocks.length < 1 && (
                  <BlankState
                    isNarrowBreakpoint={isNarrowBreakpoint}
                    addFilterButtonMobileRef={addFilterButtonMobileRef}
                    filterProviders={amendedFilterProviders}
                    addNewFilterBlock={addNewFilterBlock}
                  />
                )}
                {filterBlocks.length > 0 && (
                  <FilterList
                    addFilterButtonMobileLastRowRef={addFilterButtonMobileLastRowRef}
                    addNewFilterBlock={addNewFilterBlock}
                    deleteFilterBlock={deleteFilterBlock}
                    filterBlocks={filterBlocks}
                    filterProviders={amendedFilterProviders}
                    isNarrowBreakpoint={isNarrowBreakpoint}
                    updateFilterBlock={updateFilterBlock}
                  />
                )}
              </div>
            </div>
          )}
        />
      )}
    </>
  )
}
