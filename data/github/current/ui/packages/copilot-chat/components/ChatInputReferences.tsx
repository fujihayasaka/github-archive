import {testIdProps} from '@github-ui/test-id-props'
import {FocusKeys} from '@primer/behaviors'
import {KebabHorizontalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, Spinner, useFocusZone} from '@primer/react'
import {clsx} from 'clsx'
import {forwardRef, type RefObject, useEffect, useMemo, useRef} from 'react'

import {useIsScrolledToEnd} from '../hooks/use-is-scrolled-to-end'
import {referenceID} from '../utils/copilot-chat-helpers'
import {TopicIndexStatus, useRepoIndexingState} from '../utils/copilot-chat-hooks'
import type {CopilotChatReference, RepositoryReference} from '../utils/copilot-chat-types'
import {copilotFeatureFlags} from '../utils/copilot-feature-flags'
import {useChatState, useChatStateLens} from '../utils/CopilotChatContext'
import {useChatManager} from '../utils/CopilotChatManagerContext'
import styles from './ChatInputReferences.module.css'
import {ReferenceToken, type ReferenceTokenProps} from './ReferenceToken'

interface ChatInputReferencesProps {
  className?: string
  /** Element to return focus to when all references are deleted. */
  returnFocusRef: RefObject<HTMLElement>
  tokenSize?: 'small' | 'medium'
  isLoading?: boolean
  onClickReference?: (event: React.MouseEvent<HTMLAnchorElement>, reference: CopilotChatReference) => void
}

let renderableReferenceTypesCache: Set<CopilotChatReference['type']> | undefined = undefined

/** Set of reference types that should be rendered in the chat input when selected. */
const chatInputRenderableReferenceTypes = () =>
  (renderableReferenceTypesCache ??= new Set<CopilotChatReference['type']>([
    'figma',
    'file',
    'file-v2',
    'folder',
    'symbol',
    'image',
    'issue',
    'thread-scoped-file',
    ...(copilotFeatureFlags.topicsAsReferences ? (['repository', 'docset'] as const) : []),
  ]))

export const ChatInputReferences = ({
  className,
  isLoading,
  returnFocusRef,
  tokenSize = 'medium',
  onClickReference,
}: ChatInputReferencesProps) => {
  const {currentReferences} = useChatState()
  const manager = useChatManager()

  const scrollContainerRef = useRef<HTMLDivElement>(null)
  const scrolledToEnd = useIsScrolledToEnd(scrollContainerRef)

  const selectedReferences = useMemo(() => {
    return currentReferences.filter(reference => chatInputRenderableReferenceTypes().has(reference.type))
  }, [currentReferences])

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

  if (selectedReferences.length === 0 && !isLoading) return null

  return (
    <div role="toolbar" aria-label="Attachments" className={clsx(className, styles.container)} ref={containerRef}>
      <div
        className={clsx(styles.attachmentsList, scrolledToEnd && styles.scrolledToEnd, isLoading && styles.loading)}
        ref={scrollContainerRef}
      >
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
              onClick={onClickReference}
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
              onClick={onClickReference}
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
    </div>
  )
}

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
