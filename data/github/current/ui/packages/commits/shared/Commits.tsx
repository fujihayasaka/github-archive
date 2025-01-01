import type {RepositoryNWO} from '@github-ui/current-repository'
import {areCharacterKeyShortcutsEnabled} from '@github-ui/hotkey/keyboard-shortcuts-helper'
import {ssrSafeDocument} from '@github-ui/ssr-utils'
import type {CommandEvent} from '@github-ui/ui-commands'
import {ScopedCommands} from '@github-ui/ui-commands'
import {useNavigate} from '@github-ui/use-navigate'
import {Timeline} from '@primer/react'
import {useEffect, useRef} from 'react'

import {CommitGroup} from '../components/Commits/CommitGroup'
import {CommitsLoggingInfoProvider} from '../contexts/CommitsLoggingContext'
import {baseEmptyStateNotLoading, DeferredCommitDataProvider} from '../contexts/DeferredCommitDataContext'
import type {CommitGroup as CommitGroupType, DeferredData, LoggingInformation} from '../types/commits-types'

export type CommitsProps = {
  leadingContent?: React.ReactNode
  commitGroups: CommitGroupType[]
  trailingContent?: React.ReactNode
  repository: RepositoryNWO
  deferredCommitData?: DeferredData
  currentBlobPath?: string
  shouldClipTimeline?: boolean
  softNavToCommit?: boolean
  loggingPayload?: {[key: string]: unknown}
  loggingPrefix?: string
}

export function Commits({
  leadingContent,
  commitGroups,
  trailingContent,
  deferredCommitData = baseEmptyStateNotLoading,
  repository,
  currentBlobPath,
  loggingPayload,
  loggingPrefix,
  shouldClipTimeline = true,
  softNavToCommit = false,
}: CommitsProps) {
  const loggingInfo: LoggingInformation = {loggingPayload, loggingPrefix}
  const previouslyFocusedElement = useRef<number>(0)
  const allTopLevelListViewItems = useRef<Element[]>([])
  const navigate = useNavigate()
  const handleEnterPress = (event: React.KeyboardEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if (event.key === 'Enter') {
      const urlForCommit = ssrSafeDocument?.activeElement?.hasAttribute('data-commit-link')
        ? ssrSafeDocument?.activeElement?.getAttribute('data-commit-link')
        : undefined

      if (urlForCommit) navigate(urlForCommit)
    }
  }
  const handleKeyboardNav = (event: CommandEvent) => {
    if (
      !areCharacterKeyShortcutsEnabled() &&
      (event.commandId === 'commit-diff-view:go-down-commit' || event.commandId === 'commit-diff-view:go-up-commit')
    ) {
      return
    }
    let currentIndexIndexedAt1 = 1
    for (let i = 0; i < allTopLevelListViewItems.current.length; i++) {
      if (allTopLevelListViewItems.current[i]?.contains(ssrSafeDocument?.activeElement as Element)) {
        currentIndexIndexedAt1 = i + 1
      }
    }
    let isGoingUp = false
    if (
      event.commandId === 'commit-diff-view:go-up-commit' ||
      event.commandId === 'commit-diff-view:go-up-commit-arrow'
    ) {
      isGoingUp = true
    }

    if (previouslyFocusedElement.current !== currentIndexIndexedAt1) {
      previouslyFocusedElement.current = currentIndexIndexedAt1
    } else {
      //becasue of... some weirdness, i have no idea what exactly is going on, but when we focus the specified element it instead
      //focuses the top element of the ListView we are moving into. When going down, that's fine, but when going up we do not want
      //that. Calling the focus two times in a row solves the problem without the focus ever actually reaching the top element
      //of the list view we are entering.
      const elementToFocus = allTopLevelListViewItems.current[
        isGoingUp ? currentIndexIndexedAt1 - 2 : currentIndexIndexedAt1
      ] as HTMLElement
      elementToFocus?.focus()
      elementToFocus?.focus()
      //when we swap into a new group, we want to update the previously focused element to be the one we are on so the
      //user can navigate back to the group they were in previously without having to double tap in that direction
      previouslyFocusedElement.current = isGoingUp ? currentIndexIndexedAt1 - 1 : currentIndexIndexedAt1 + 1
    }
  }
  useEffect(() => {
    const timeout = setTimeout(() => {
      const allStuff = document.querySelectorAll('[id*="-list-view-node-"]')
      allTopLevelListViewItems.current = Array.from(allStuff)
    }, 0)

    return () => clearTimeout(timeout)
  }, [commitGroups])

  return (
    <DeferredCommitDataProvider deferredData={deferredCommitData}>
      <CommitsLoggingInfoProvider loggingInfo={loggingInfo}>
        <Timeline clipSidebar onKeyDown={handleEnterPress}>
          {leadingContent}
          <ScopedCommands
            commands={{
              'commit-diff-view:go-down-commit-arrow': handleKeyboardNav,
              'commit-diff-view:go-down-commit': handleKeyboardNav,
              'commit-diff-view:go-up-commit-arrow': handleKeyboardNav,
              'commit-diff-view:go-up-commit': handleKeyboardNav,
            }}
          >
            {commitGroups.map((commitGroup, index) => {
              return (
                <CommitGroup
                  key={commitGroup.title}
                  title={commitGroup.title}
                  commits={commitGroup.commits}
                  shouldClipTimeline={shouldClipTimeline && index === 0}
                  currentBlobPath={currentBlobPath}
                  repo={repository}
                  softNavToCommit={softNavToCommit}
                />
              )
            })}
          </ScopedCommands>
          {trailingContent}
        </Timeline>
      </CommitsLoggingInfoProvider>
    </DeferredCommitDataProvider>
  )
}
