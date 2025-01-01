import {testIdProps} from '@github-ui/test-id-props'
import {useLayoutEffect} from '@github-ui/use-layout-effect'
import {FocusKeys} from '@primer/behaviors'
import {FileIcon, KebabHorizontalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, Button, IconButton, Spinner, useFocusZone} from '@primer/react'
import {clsx} from 'clsx'
import type React from 'react'
import {
  forwardRef,
  type KeyboardEventHandler,
  memo,
  type RefObject,
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
} from 'react'

import {useIsScrolledToEnd} from '../hooks/use-is-scrolled-to-end'
import {getRenderableReferences, referenceID, referencesAreEqual} from '../utils/copilot-chat-helpers'
import {TopicIndexStatus, useRepoIndexingState} from '../utils/copilot-chat-hooks'
import type {CopilotChatReference, RepositoryReference} from '../utils/copilot-chat-types'
import {useChatState, useChatStateLens} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './ChatInputReferences.module.css'
import {ReferenceToken, type ReferenceTokenProps, RemoveReferenceTokenButton} from './ReferenceToken'

interface ChatInputReferencesProps {
  className?: string
  /** Element to return focus to when all references are deleted. */
  returnFocusRef: RefObject<HTMLElement>
  tokenSize?: 'small' | 'medium'
  isLoading?: boolean
  onSelectReference?: (reference: CopilotChatReference, event?: React.MouseEvent<HTMLAnchorElement>) => void
  getReferenceVersion?: (reference: CopilotChatReference) => number | undefined
  showConvertToFileText?: boolean
  onConvertToFile?: () => void
  onConvertToFileDismiss?: () => void
}

export const ChatInputReferences = memo(
  ({
    className,
    isLoading,
    returnFocusRef,
    tokenSize = 'medium',
    onSelectReference,
    getReferenceVersion,
    showConvertToFileText,
    onConvertToFile,
    onConvertToFileDismiss,
  }: ChatInputReferencesProps) => {
    const {currentReferences} = useChatState()
    const manager = useChatManager()

    const scrollContainerRef = useRef<HTMLDivElement>(null)
    const scrolledToEnd = useIsScrolledToEnd(scrollContainerRef)
    const [hoveringDismissConvertToFile, setHoveringDismissConvertToFile] = useState(false)

    const selectedReferences = useMemo(() => getRenderableReferences(currentReferences), [currentReferences])

    const containerRef = useRef<HTMLDivElement>(null)
    useFocusZone(
      {
        containerRef,
        focusableElementFilter: el => !el.hasAttribute('aria-hidden'),
        bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
        focusInStrategy: 'previous',
        focusOutBehavior: 'stop',
      },
      [selectedReferences],
    )

    const tokensRef = useRef<Array<HTMLAnchorElement | null>>([])
    const onRemove = (reference: CopilotChatReference, index: number) => {
      const nextFocusTarget = tokensRef.current[index + 1] ?? tokensRef.current[index - 1] ?? returnFocusRef.current
      nextFocusTarget?.focus()

      manager.removeReference(reference)
    }

    const onRemoveAll = () => {
      // setTimeout to delay so we pull focus after the ActionMenu tries to return focus to its (now nonexistent) anchor
      setTimeout(() => returnFocusRef.current?.focus())
      manager.clearCurrentReferences()
    }

    // Scroll to the token that was most recently added
    const prevSelectedReferences = useRef<CopilotChatReference[]>(selectedReferences)
    useLayoutEffect(() => {
      if (prevSelectedReferences.current.length < selectedReferences.length) {
        const newReference = selectedReferences.find(
          reference => !prevSelectedReferences.current.find(prevRef => referencesAreEqual(prevRef, reference)),
        )
        const lastIndex = newReference ? selectedReferences.indexOf(newReference) : -1
        tokensRef?.current?.[lastIndex]?.scrollIntoView({behavior: 'smooth', inline: 'end'})
      }
      prevSelectedReferences.current = selectedReferences
    }, [selectedReferences])

    const handleConvertToDismiss = useCallback(() => {
      setHoveringDismissConvertToFile(false)
      onConvertToFileDismiss?.()
    }, [onConvertToFileDismiss])

    const descriptionId = useId()

    const onKeyDown: KeyboardEventHandler<HTMLButtonElement> = event => {
      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      if (event.key === 'Delete' || event.key === 'Backspace') {
        event.preventDefault()
        event.stopPropagation()
        handleConvertToDismiss()
      }
    }

    if (selectedReferences.length === 0 && !isLoading && !showConvertToFileText) return null

    return (
      <div role="toolbar" aria-label="Attachments" className={clsx(className, styles.container)} ref={containerRef}>
        <div
          className={clsx(styles.attachmentsList, scrolledToEnd && styles.scrolledToEnd, isLoading && styles.loading)}
          ref={scrollContainerRef}
        >
          {showConvertToFileText && (
            <Button
              onClick={onConvertToFile}
              leadingVisual={FileIcon}
              className={clsx(
                styles.convertToFileButton,
                hoveringDismissConvertToFile && styles.hoveringDismissConvertToFile,
              )}
              aria-describedby={descriptionId}
              onKeyDown={onKeyDown}
            >
              <div className={styles.convertToFileButtonContent}>
                Convert to file
                <RemoveReferenceTokenButton
                  size={tokenSize}
                  onRemove={handleConvertToDismiss}
                  descriptionId={descriptionId}
                  onMouseOver={() => setHoveringDismissConvertToFile(true)}
                  onMouseLeave={() => setHoveringDismissConvertToFile(false)}
                />
              </div>
            </Button>
          )}
          {selectedReferences.map((reference, index) =>
            reference.type === 'repository' ? (
              <RepoReferenceToken
                reference={reference}
                key={referenceID(reference)}
                ref={el => {
                  tokensRef.current[index] = el
                }}
                data-index={index}
                size={tokenSize}
                onRemove={() => onRemove(reference, index)}
                onClick={onSelectReference}
                getReferenceVersion={getReferenceVersion}
              />
            ) : (
              <ReferenceToken
                reference={reference}
                key={referenceID(reference)}
                ref={el => {
                  tokensRef.current[index] = el
                }}
                data-index={index}
                size={tokenSize}
                onRemove={() => onRemove(reference, index)}
                onClick={onSelectReference}
                getReferenceVersion={getReferenceVersion}
              />
            ),
          )}

          {isLoading && (
            <div className={styles.functionLoading} {...testIdProps('loading-indicator')}>
              <Spinner size="small" />
              Retrieving…
            </div>
          )}
        </div>

        {selectedReferences.length > 0 && (
          <>
            <div className={styles.divider} />
            <ActionMenu>
              <ActionMenu.Anchor>
                <IconButton
                  icon={KebabHorizontalIcon}
                  aria-label="Attachments options"
                  variant="invisible"
                  tooltipDirection="n"
                  className={styles.menuButton}
                  size={tokenSize}
                />
              </ActionMenu.Anchor>

              <ActionMenu.Overlay width="small">
                <ActionList>
                  <ActionList.Item onSelect={onRemoveAll}>
                    <ActionList.LeadingVisual>
                      <TrashIcon />
                    </ActionList.LeadingVisual>
                    Remove attachments
                  </ActionList.Item>
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </>
        )}
      </div>
    )
  },
)

ChatInputReferences.displayName = 'ChatInputReferences'

/**
 * It's just a ReferenceToken but it automatically kicks off repo indexing when mounted (if needed).
 */
const RepoReferenceToken = forwardRef<HTMLAnchorElement, ReferenceTokenProps & {reference: RepositoryReference}>(
  function RepoReferenceToken(props, ref) {
    const repo = props.reference
    const indexingAllowed = useChatStateLens(s => s.model && !s.model.hasLimitedCapabilities)

    const nameWithOwner = `${repo.ownerLogin}/${repo.name}`

    const [indexingState, triggerIndexing] = useRepoIndexingState(nameWithOwner)

    const autoTriggeredIndexing = useRef(false)

    const isNotIndexed =
      indexingState.code === TopicIndexStatus.Unindexed || indexingState.docs === TopicIndexStatus.Unindexed

    useEffect(
      function startIndexing() {
        if (!autoTriggeredIndexing.current && isNotIndexed && indexingAllowed) {
          autoTriggeredIndexing.current = true
          triggerIndexing()
        }
      },
      [indexingAllowed, isNotIndexed, triggerIndexing],
    )

    return <ReferenceToken ref={ref} {...props} />
  },
)
