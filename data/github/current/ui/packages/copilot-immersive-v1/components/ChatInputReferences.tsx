import {ReferenceToken} from '@github-ui/copilot-chat/components/ReferenceToken'
import {referenceID} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useChatState} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/utils/CopilotChatManagerContext'
import {FocusKeys} from '@primer/behaviors'
import {KebabHorizontalIcon, TrashIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useFocusZone} from '@primer/react'
import {clsx} from 'clsx'
import {type RefObject, useEffect, useMemo, useRef, useState} from 'react'

import styles from './ChatInputReferences.module.css'

interface ChatInputReferencesProps {
  className?: string
  /** Element to return focus to when all references are deleted. */
  returnFocusRef: RefObject<HTMLElement>
}

const supportedReferenceTypes = new Set<CopilotChatReference['type']>(['file', 'file-v2', 'symbol'])

export const ChatInputReferences = ({className, returnFocusRef}: ChatInputReferencesProps) => {
  const {currentReferences} = useChatState()
  const manager = useChatManager()

  const scrollContainerRef = useRef<HTMLDivElement>(null)
  const [scrolledToEnd, setScrolledToEnd] = useState(false)
  useEffect(() => {
    const root = scrollContainerRef.current
    const lastChild = root?.lastElementChild
    if (!lastChild) return

    const observer = new IntersectionObserver(([entry]) => setScrolledToEnd(entry?.isIntersecting ?? true), {
      root,
      threshold: 1,
    })

    observer.observe(lastChild)
    return () => observer.disconnect()
  })

  const selectedFileReferences = useMemo(
    () =>
      currentReferences
        .map((reference, i) => ({reference, originalIndex: i}))
        .filter(({reference}) => supportedReferenceTypes.has(reference.type)),
    [currentReferences],
  )

  const containerRef = useRef<HTMLDivElement>(null)
  useFocusZone(
    {
      containerRef,
      focusableElementFilter: el => !el.hasAttribute('aria-hidden'),
      bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
      focusInStrategy: 'previous',
      focusOutBehavior: 'stop',
    },
    [selectedFileReferences],
  )

  const tokensRef = useRef<Array<HTMLAnchorElement | null>>([])
  const onRemove = (originalIndex: number, index: number) => {
    const nextFocusTarget = tokensRef.current[index + 1] ?? tokensRef.current[index - 1] ?? returnFocusRef.current
    nextFocusTarget?.focus()

    manager.removeReference(originalIndex)
  }

  const onRemoveAll = () => {
    // setTimeout to delay so we pull focus after the ActionMenu tries to return focus to its (now nonexistent) anchor
    setTimeout(() => returnFocusRef.current?.focus())
    manager.clearCurrentReferences()
  }

  if (selectedFileReferences.length === 0) return null

  return (
    <div role="toolbar" aria-label="Attachments" className={clsx(className, styles.container)} ref={containerRef}>
      <div className={clsx(styles.attachmentsList, scrolledToEnd && styles.scrolledToEnd)} ref={scrollContainerRef}>
        {selectedFileReferences.map(({reference, originalIndex}, index) => (
          <ReferenceToken
            reference={reference}
            onRemove={() => onRemove(originalIndex, index)}
            size="medium"
            key={referenceID(reference)}
            data-index={index}
            ref={el => {
              tokensRef.current[index] = el
            }}
          />
        ))}
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
