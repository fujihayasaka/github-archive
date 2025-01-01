import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {announce} from '@github-ui/aria-live'
import {type TestIdProps, testIdProps} from '@github-ui/test-id-props'
import {useAnalytics} from '@github-ui/use-analytics'
import {type ResponsiveValue, useResponsiveValue} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {useCallback, useEffect, useImperativeHandle, useState} from 'react'

import {AdvancedFilterDialog} from './advanced-filter-dialog/AdvancedFilterDialog'
import {ClearButton} from './clear-button/ClearButton'
import {defaultFilterSettings} from './constants/defaults'
import {Strings} from './constants/strings'
import {FilterContextProvider} from './context/RootContext'
import styles from './Filter.module.css'
import {FilterQuery} from './filter-query'
import {FilterInputIcon} from './FilterInputIcon'
import {FilterInputWrapper} from './FilterInputWrapper'
import {Input} from './input/Input'
import {SubmitButton} from './input/SubmitButton'
import {SuggestionsList} from './suggestions/SuggestionsList'
import type {FilterButtonVariant, FilterProvider, FilterSettings, FilterVariant, SubmitEvent} from './types'
import {ValidationMessage} from './ValidationMessage'

// Exports from the root of the package
export * from './constants/defaults'
export * from './filter-query'
export * from './FilterRevert'
export * from './types'
export * from './ValidationMessage'

export type AdvancedFilterDialogRef = {
  isAdvancedFilterDialogOpen: boolean
  toggleAdvancedFilterDialog: (open?: boolean) => void
}

export type FilterProps = {
  /** ID of the Filter Component */
  id: string
  /** CSS class to apply at the root element of the component */
  className?: string
  /** Change event callback, passing the updated filter value */
  onChange?: (value: string) => void
  /** Event callback, triggered by the filter query being parsed, and passing the updated filter query request*/
  onParse?: (request: FilterQuery) => void
  /** Submit event callback, triggered by Enter or pressing Submit, and passing the updated filter query and the
   * originating event type */
  onSubmit?: (request: FilterQuery, eventType: SubmitEvent) => void
  /** Array of FilterProviders that are being used/supported */
  providers: FilterProvider[]
  /** React Ref to the input element */
  advancedFilterDialogRef?: React.RefObject<AdvancedFilterDialogRef>
  /** Context to be applied for all API queries */
  context?: Record<string, string>
  /** Variant of the filter button, whether to show the title or just the icon */
  filterButtonVariant?: FilterButtonVariant
  /** Initial value to use for the input. DO NOT USE in conjunction with `filterValue`.
   * Only use this if you want the Filter to have an initial value but remain uncontrolled. */
  initialFilterValue?: string
  /** Supplied filter value to use. By using this, the Filter is externally controlled
   * and will not use it's own state. */
  filterValue?: string
  /** React Ref to the input element */
  inputRef?: React.RefObject<HTMLInputElement>
  /** Label displayed atop the Filter bar. This is only shown when `visuallyHideLabel` is `false` */
  label: string
  /** Input keydown event callback */
  onKeyDown?: React.KeyboardEventHandler
  /** Validation callback, passing the validation message and the validation query */
  onValidation?: (messages: string[], filterQuery: FilterQuery) => void
  /** Placeholder text for the input */
  placeholder?: string
  /** Settings for the Filter, such as support of the legacy No filter provider and alias matching */
  settings?: FilterSettings
  /** Whether to show any validation messages or not. If this is disabled, use `onValidation` to receive the messages to display elsewhere */
  showValidationMessage?: boolean
  /** Variant of the Filter to render. `button` or `input` for one or the other, `full` (default) renders both.  */
  variant?: FilterVariant
  /** Whether to visually hide the Label or not */
  visuallyHideLabel?: boolean
} & TestIdProps

const defaultFilterQuery = new FilterQuery()

export const FilterInternal = ({
  advancedFilterDialogRef,
  className,
  context,
  'data-testid': dataTestId,
  filterButtonVariant = 'normal',
  filterValue,
  id,
  initialFilterValue,
  inputRef,
  label,
  onChange,
  onParse,
  onSubmit,
  onKeyDown,
  onValidation,
  placeholder,
  providers,
  settings,
  showValidationMessage = true,
  variant = 'full',
  visuallyHideLabel = true,
}: FilterProps) => {
  const [validationMessage, setValidationMessage] = useState<string[]>([])
  const hasValidationMessage = showValidationMessage && validationMessage.length > 0
  const {sendAnalyticsEvent} = useAnalytics()

  const validationCallback = useCallback(
    (messages: string[] = [], filterQuery: FilterQuery = defaultFilterQuery) => {
      // Only updates array when the validation message changes
      if (JSON.stringify(validationMessage) !== JSON.stringify(messages)) setValidationMessage(messages)
      onValidation?.(messages, filterQuery)
    },
    [onValidation, validationMessage],
  )

  const filterButtonResponsive = useResponsiveValue<ResponsiveValue<FilterButtonVariant>, FilterButtonVariant>(
    {regular: filterButtonVariant, narrow: variant === 'button' ? 'normal' : 'compact'},
    filterButtonVariant,
  )

  const externallyControlled = typeof filterValue === 'string'
  const [innerValue, setInnerValue] = useState<string>(initialFilterValue || '')

  const changeCallback = useCallback(
    (value: string) => {
      if (!externallyControlled) {
        setInnerValue(value)
      }
      onChange?.(value)
    },
    [externallyControlled, onChange],
  )

  useEffect(() => {
    if (validationMessage.length > 0) {
      const userFriendlyMessage = validationMessage.map(s => s.replaceAll(/<pre>|<\/pre>/g, "'")).join('. ')
      const announcement = `${Strings.filterInvalid(validationMessage.length)} ${userFriendlyMessage}.`
      announce(announcement)
      sendAnalyticsEvent('filter.validation_errors', 'FILTER_VALIDATION_ERRORS', {messages: userFriendlyMessage})
    }
  }, [sendAnalyticsEvent, validationMessage])

  const leftRounded = variant === 'input'
  const rightRounded = (variant === 'input' && !onSubmit) || (variant !== 'input' && !onSubmit)

  const [isAdvancedFilterDialogOpen, setAdvancedFilterDialogOpen] = useState(false)

  useImperativeHandle(
    advancedFilterDialogRef,
    () => ({
      isAdvancedFilterDialogOpen,
      toggleAdvancedFilterDialog: (open?: boolean) => setAdvancedFilterDialogOpen(open ?? !isAdvancedFilterDialogOpen),
    }),
    [isAdvancedFilterDialogOpen],
  )

  return (
    <FilterContextProvider
      context={context}
      inputRef={inputRef}
      rawFilter={externallyControlled ? filterValue : innerValue}
      onChange={changeCallback}
      onParse={onParse}
      onSubmit={onSubmit}
      onValidation={validationCallback}
      providers={providers}
      settings={{...defaultFilterSettings, ...settings}}
      variant={variant}
    >
      <div
        id={id}
        role="form"
        className={clsx('FormControl FormControl--fullWidth', className, styles.Box_1)}
        {...testIdProps(dataTestId ?? 'filter')}
      >
        <label
          id={`${id}-label`}
          htmlFor={`${id}-input`}
          className={`FormControl-label ${visuallyHideLabel ? 'sr-only' : ''}`}
          {...testIdProps('filter-bar-label')}
        >
          {label}
        </label>
        <div className={styles.Box_0}>
          <FilterInputWrapper isStandalone={variant === 'button'}>
            {variant !== 'input' && (
              <AdvancedFilterDialog
                isStandalone={variant === 'button'}
                filterButtonVariant={filterButtonResponsive}
                dialogOpen={isAdvancedFilterDialogOpen}
                setDialogOpen={setAdvancedFilterDialogOpen}
              />
            )}
            {variant !== 'button' && (
              <>
                <div
                  className={clsx(
                    styles.Box_2,
                    leftRounded && styles.leftRounded,
                    rightRounded && styles.rightRounded,
                    onSubmit && styles.hasSubmit,
                  )}
                >
                  {!onSubmit && <FilterInputIcon />}
                  <Input
                    id={id}
                    placeholder={placeholder}
                    onKeyDown={onKeyDown}
                    hasValidationMessage={hasValidationMessage}
                  />
                  <ClearButton />
                </div>
                {onSubmit && <SubmitButton />}
              </>
            )}
          </FilterInputWrapper>
          <SuggestionsList id={id} />
          {/* This needs to move outside the Filter component because we can't predict where the consumer wants to put the error message. In memex this would go above the table view. */}
          {showValidationMessage && <ValidationMessage messages={validationMessage} id={`${id}-validation-message`} />}
        </div>
      </div>
    </FilterContextProvider>
  )
}

FilterInternal.displayName = 'FilterInternal'

const analyticsMetadata = {}
export const Filter = (props: FilterProps) => (
  <AnalyticsProvider appName="shared_components" category="filter" metadata={analyticsMetadata}>
    <FilterInternal {...props} />
  </AnalyticsProvider>
)
Filter.displayName = 'Filter'
