import {BugIcon, ChevronLeftIcon, ChevronRightIcon, LightBulbIcon, PaperclipIcon} from '@primer/octicons-react'
import {ActionList, Button, Dialog, IconButton, registerPortalRoot} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import {clsx} from 'clsx'
import {useEffect, useRef, useState} from 'react'

import {getErrorSourceLabel, type SparkError} from '../utilities/error'
import {ErrorDisplay} from './ErrorDisplay'
import styles from './Suggestions.module.css'

interface SuggestionsProps {
  suggestions: string[] | undefined
  errors: Array<SparkError & {attached: boolean; dismissed?: boolean}>
  onSelectSuggestion: (v: string) => void
  attachAll: (attached: boolean) => void
  fixAll: () => void
  isFetching: boolean
}

const Suggestions = ({suggestions, errors, onSelectSuggestion, attachAll, fixAll, isFetching}: SuggestionsProps) => {
  const [isExpanded, setIsExpanded] = useState<boolean>(false)
  const hasAutoCollapsedRef = useRef(false)
  const visibleErrors = errors.filter(e => !e.dismissed)
  const hasErrors = !isFetching && visibleErrors.length > 0
  const [dialogIndex, setDialogIndex] = useState<number>()
  const [userExpandedSuggestions, setUserExpandedSuggestions] = useState<boolean>(true)

  useEffect(() => {
    if (isFetching) {
      // Starting a new fetch cycle
      if (!hasAutoCollapsedRef.current) {
        setIsExpanded(false)
        hasAutoCollapsedRef.current = true
      }
    } else {
      // Fetching finished
      hasAutoCollapsedRef.current = false // reset
      if (userExpandedSuggestions) {
        setIsExpanded(true)
      }
    }
  }, [isFetching, userExpandedSuggestions])

  // This is for a workaround to ensure the Overlay renders in the example box
  const exampleBoxRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (exampleBoxRef.current) {
      registerPortalRoot(exampleBoxRef.current, 'exampleBox-dialog')
    }
  }, [exampleBoxRef])

  const ariaLabel = hasErrors
    ? isExpanded
      ? 'Hide errors'
      : 'Show errors'
    : isExpanded
      ? 'Hide suggestions'
      : 'Show suggestions'

  const actionListId = hasErrors ? 'error-list' : 'suggestion-list'

  const copyErrorText = (text: string) => {
    const formattedText = text.replace(/\s+/g, ' ').trim()
    navigator.clipboard.writeText(formattedText)
  }

  return (
    <div className={styles.container}>
      <div className={clsx(styles.header, hasErrors && !errors.some(error => !error.attached) && 'mb-2')}>
        <span className={clsx(styles.headerSummary, !hasErrors && !isExpanded && 'mb-2')}>
          <Button
            variant="invisible"
            aria-expanded={isExpanded}
            aria-controls={actionListId}
            className="px-2 bgColor-transparent"
            onClick={() => {
              setIsExpanded(prev => {
                const next = !prev
                setUserExpandedSuggestions(next)
                return next
              })
            }}
            aria-label={ariaLabel}
          >
            <ChevronRightIcon className={clsx(styles.chevron, 'fgColor-muted')} data-expanded={isExpanded} />
          </Button>
          {hasErrors ? (
            <span className={`${styles.headerText} ${styles.headerTextError}`}>{`${errors.length} Error${
              errors.length === 1 ? '' : 's'
            }`}</span>
          ) : (
            <span className={styles.headerText}>Suggestions</span>
          )}
        </span>
        {hasErrors && (
          <div className="d-flex flex-row gap-1">
            <Button
              className="ml-auto"
              size="small"
              variant="default"
              leadingVisual={PaperclipIcon}
              onClick={() => attachAll(true)}
            >
              Attach
            </Button>
            <Button size="small" variant="primary" onClick={fixAll}>
              Fix all
            </Button>
          </div>
        )}
      </div>
      {!hasErrors && suggestions && !isFetching && (
        <div id={actionListId} className={clsx(isExpanded ? styles.expanded : styles.collapsed)}>
          <ActionList className={clsx(styles.suggestionsList, 'pb-2')}>
            {suggestions.map((suggestion, i) => (
              <ActionList.Item key={i} onSelect={() => onSelectSuggestion(suggestion)} role="button" tabIndex={0}>
                <ActionList.LeadingVisual>
                  <LightBulbIcon className={styles.suggestionIcon} />
                </ActionList.LeadingVisual>
                {suggestion}
              </ActionList.Item>
            ))}
          </ActionList>
        </div>
      )}
      {isFetching && !hasErrors && (
        <div className={clsx(isExpanded ? styles.expanded : styles.collapsed)}>
          <SuggestionSkeleton />
        </div>
      )}
      {hasErrors && errors.some(error => !error.attached) && (
        <div
          id={actionListId}
          className={clsx(styles.suggestionsList, 'pb-2 mx-2', isExpanded ? styles.expanded : styles.collapsed)}
        >
          <ActionList variant="full">
            {errors.map((e, i) =>
              e.attached || e.dismissed ? null : (
                <div key={e.messageRaw} className={styles.errorContainer}>
                  <ActionList.Item
                    data-testid={`attach-error-${i}`}
                    onSelect={() => {
                      setDialogIndex(i)
                    }}
                    className={styles.actionListItem}
                  >
                    <ActionList.LeadingVisual>
                      <BugIcon className="fgColor-danger" />
                    </ActionList.LeadingVisual>
                    <ErrorDisplay error={e} truncate />
                  </ActionList.Item>
                </div>
              ),
            )}
          </ActionList>
        </div>
      )}
      {(!!dialogIndex || dialogIndex === 0) && (
        <Dialog
          onClose={() => setDialogIndex(undefined)}
          title={getErrorSourceLabel(errors[dialogIndex]?.source)}
          renderFooter={() => (
            <div className={`border-top ${styles.dialogFooter}`}>
              {errors.length > 1 && (
                <>
                  <IconButton
                    aria-label="Previous error"
                    size="small"
                    variant="invisible"
                    icon={ChevronLeftIcon}
                    onClick={() => {
                      setDialogIndex(prev => {
                        if (prev === undefined) return prev
                        if (prev === 0) return errors.length - 1
                        return prev - 1
                      })
                    }}
                  />
                  <span className="fgColor-muted">
                    {`${errors.findIndex((e, i) => i === dialogIndex) + 1} / ${errors.length}`}
                  </span>
                  <IconButton
                    aria-label="Next error"
                    size="small"
                    variant="invisible"
                    icon={ChevronRightIcon}
                    onClick={() => {
                      setDialogIndex(prev => {
                        if (prev === undefined) return prev
                        if (prev === errors.length - 1) return 0
                        return prev + 1
                      })
                    }}
                  />
                </>
              )}
              <Button
                size="small"
                variant="default"
                className="ml-auto"
                onClick={() => copyErrorText(errors[dialogIndex]?.messageRaw || '')}
              >
                Copy
              </Button>
              <Button
                size="small"
                variant="default"
                leadingVisual={PaperclipIcon}
                onClick={() => {
                  attachAll(true)
                  setDialogIndex(undefined)
                }}
              >
                Attach
              </Button>
              <Button
                size="small"
                variant="primary"
                onClick={() => {
                  fixAll()
                  setDialogIndex(undefined)
                }}
              >
                Fix all
              </Button>
            </div>
          )}
          renderBody={() => (
            <div className={styles.errorContentContainer}>
              {errors[dialogIndex] && (
                <ErrorDisplay error={errors[dialogIndex]} linkCallback={() => setDialogIndex(undefined)} />
              )}
            </div>
          )}
        />
      )}
    </div>
  )
}

const SuggestionSkeleton = () => {
  const widths = [60, 70, 80]
  return (
    <div className="px-3 pb-2">
      {widths.map(w => {
        // eslint-disable-next-line primer-react/no-system-props
        return <SkeletonText key={w} lines={1} maxWidth={`${w}%`} className="mb-2" />
      })}
    </div>
  )
}

export default Suggestions
