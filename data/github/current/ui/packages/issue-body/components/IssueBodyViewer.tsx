import {isLoggedIn} from '@github-ui/client-env'
import {IssueMarkdownViewer} from '@github-ui/commenting/IssueMarkdownViewer'
import {CopilotPlanBrainstormButton} from '@github-ui/copilot-plan-brainstorm/CopilotPlanBrainstormButton'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {ReactionViewerAnchor} from '@github-ui/reaction-viewer/ReactionViewerAnchor'
import type {SafeHTMLString} from '@github-ui/safe-html'
import {AddSubIssueButtonGroup} from '@github-ui/sub-issues/AddSubIssueButtonGroup'
import {useCanEditSubIssues} from '@github-ui/sub-issues/useCanEditSubIssues'
import {useHasSubIssues} from '@github-ui/sub-issues/useHasSubIssues'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import type {TaskItem} from '@github-ui/use-tasklist'
import {useSafeTimeout} from '@primer/react'
import {type RefObject, Suspense, useCallback, useMemo} from 'react'
import React from 'react'
import {graphql, useFragment, useRelayEnvironment} from 'react-relay'

import {ERRORS} from '../constants/errors'
import {commitCreateIssueFromChecklistItemMutation} from '../mutations/create-issue-from-checklist-item-mutation'
import {commitCreateSubIssueFromChecklistItemMutation} from '../mutations/create-sub-issue-from-checklist-item-mutation'
import {commitUpdateIssueBodyMutation} from '../mutations/update-issue-body-mutation'
import type {IssueBodyViewer$key} from './__generated__/IssueBodyViewer.graphql'
import type {IssueBodyViewerReactable$key} from './__generated__/IssueBodyViewerReactable.graphql'
import type {IssueBodyViewerSubIssues$key} from './__generated__/IssueBodyViewerSubIssues.graphql'
import classes from './IssueBodyViewer.module.css'

const ReactionViewerRelay = React.lazy(() => import('@github-ui/reaction-viewer/ReactionViewerRelay'))

export type IssueBodyViewerProps = {
  html: SafeHTMLString
  markdown: string
  comment: IssueBodyViewer$key
  onLinkClick?: (event: MouseEvent) => void
  markdownViewerRef?: RefObject<HTMLDivElement>
  issueBodyRef?: React.RefObject<HTMLDivElement>
  bodyVersion: string
  viewerCanUpdate: boolean
  locked: boolean
  reactable: IssueBodyViewerReactable$key
  subIssues?: IssueBodyViewerSubIssues$key | null
  title?: string
  insideSidePanel?: boolean
  repositoryId?: string
  onIssueEditStateChange?: (edited: boolean) => void
  copilotApiUrl?: string
  nameWithOwner?: string
}

export function IssueBodyViewer({
  html,
  markdown,
  comment,
  onLinkClick,
  issueBodyRef,
  bodyVersion,
  locked,
  viewerCanUpdate,
  reactable,
  subIssues = null,
  title,
  insideSidePanel,
  repositoryId,
  onIssueEditStateChange,
  copilotApiUrl,
  nameWithOwner,
}: IssueBodyViewerProps) {
  const {copilot_plan_brainstorm_with_blackbird} = useFeatureFlags()
  const environment = useRelayEnvironment()
  const {safeSetTimeout, safeClearTimeout} = useSafeTimeout()
  const data = useFragment(
    graphql`
      fragment IssueBodyViewer on Comment {
        id
      }
    `,
    comment,
  )
  const dataReaction = useFragment(
    graphql`
      fragment IssueBodyViewerReactable on Reactable {
        ...ReactionViewerRelayGroups
      }
    `,
    reactable,
  )
  const dataSubIssues = useFragment(
    graphql`
      fragment IssueBodyViewerSubIssues on Issue {
        ...useCanEditSubIssues
        ...useHasSubIssues
        ...AddSubIssueButtonGroup @arguments(fetchSubIssues: false)
      }
    `,
    subIssues,
  )

  const hasSubIssues = useHasSubIssues(dataSubIssues)
  const canEditSubIssues = useCanEditSubIssues(dataSubIssues)
  const showAddSubIssueButton = canEditSubIssues && dataSubIssues && !hasSubIssues

  const onSave = useCallback(
    (newBody: string, onCompleted: () => void, onError: () => void) => {
      commitUpdateIssueBodyMutation({
        environment,
        input: {issueId: data.id, body: newBody, bodyVersion},
        onCompleted,
        onError,
      })
    },
    [bodyVersion, environment, data.id],
  )

  const {addToast} = useToastContext()

  /**
   * * Handles conversion completion timing - can't immediately set isConverting to false
   * because UI updates (rendering converted items as links) happen asynchronously.
   * Uses MutationObserver to wait for DOM changes ensuring loading state persists
   * until visual conversion is complete.
   **/
  const handleConversionComplete = useCallback(
    (
      id: string,
      setIsConverting: (isConverting: boolean) => void,
      onCompletedCallback?: () => void,
      convertingToSubIssue = false,
    ) => {
      let timeoutId: ReturnType<typeof safeSetTimeout> | null = null

      const completeMutation = () => {
        setIsConverting(false)
        onCompletedCallback?.()

        if (timeoutId) {
          safeClearTimeout(timeoutId)
        }
      }

      if (convertingToSubIssue) {
        // No need for observation as the rerender is triggered immediately
        requestAnimationFrame(() => {
          completeMutation()
        })
        return
      }

      const observer = new MutationObserver(mutationsList => {
        for (const mutation of mutationsList) {
          if (mutation.type === 'childList') {
            const safeHTMLBox = document.querySelector(`#checkbox-item-${id}`)

            if (safeHTMLBox?.querySelector('a')) {
              observer.disconnect()
              completeMutation()
              return
            }
          }
        }
      })

      // Observing the closest element that doesn't rerender on mutation complete
      const issueContainer = document.getElementById('issue-body-viewer')
      if (issueContainer) {
        observer.observe(issueContainer, {childList: true, subtree: true})
      } else {
        completeMutation()
        return
      }

      // If we don't find the newly inserted link, disconnect
      timeoutId = safeSetTimeout(() => {
        observer.disconnect()
        completeMutation()
      }, 3000)
    },
    [safeSetTimeout, safeClearTimeout],
  )

  const onConvertToIssue = useCallback(
    (
      task: TaskItem,
      setIsConverting: (converting: boolean) => void,
      onCompletedCallback?: () => void,
      onErrorCallback?: (error: Error) => void,
    ) => {
      if (!(repositoryId && onIssueEditStateChange)) return

      setIsConverting(true)
      commitCreateIssueFromChecklistItemMutation({
        environment,
        input: {parentIssueId: data.id, repositoryId, title: task.title, position: task.position},
        onCompleted: () => {
          onIssueEditStateChange?.(true)
          handleConversionComplete(task.id, setIsConverting, onCompletedCallback)
        },
        onError: error => {
          // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
          addToast({type: 'error', message: ERRORS.couldNotConvertIssue})
          setIsConverting(false)
          onErrorCallback?.(error)
        },
      })
    },
    [repositoryId, onIssueEditStateChange, environment, data.id, addToast, handleConversionComplete],
  )

  const onConvertToSubIssue = useMemo(
    () =>
      (
        task: TaskItem,
        setIsConverting: (converting: boolean) => void,
        onCompletedCallback?: () => void,
        onErrorCallback?: (error: Error) => void,
      ) => {
        if (!(repositoryId && onIssueEditStateChange)) return

        setIsConverting(true)
        commitCreateSubIssueFromChecklistItemMutation({
          environment,
          input: {
            parentIssueId: data.id,
            repositoryId,
            body: markdown,
            position: task.position as [number, number],
          },
          onCompleted: () => {
            onIssueEditStateChange?.(true)
            handleConversionComplete(task.id, setIsConverting, onCompletedCallback, true)
          },
          onError: error => {
            // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
            addToast({type: 'error', message: ERRORS.couldNotConvertIssue})
            setIsConverting(false)
            onErrorCallback?.(error)
          },
        })
      },
    [repositoryId, onIssueEditStateChange, environment, data.id, addToast, markdown, handleConversionComplete],
  )

  const showCopilotPlanBrainstormButton = copilot_plan_brainstorm_with_blackbird

  return (
    <div className={classes.IssueBody} ref={issueBodyRef} id="issue-body-viewer">
      <IssueMarkdownViewer
        html={html}
        markdown={markdown}
        viewerCanUpdate={viewerCanUpdate}
        onSave={onSave}
        onLinkClick={onLinkClick}
        onConvertToIssue={onConvertToIssue}
        onConvertToSubIssue={onConvertToSubIssue}
      />
      <div className={classes.IssueBodyTaskList}>
        {showAddSubIssueButton && (
          <div className={classes.IssueBodySubIssueButtonContainer}>
            <AddSubIssueButtonGroup issue={dataSubIssues} insideSidePanel={insideSidePanel} />
          </div>
        )}
        {showCopilotPlanBrainstormButton && copilotApiUrl && (
          <div
            className={classes.IssueBodyPlanBrainstormButtonContainer}
            data-testid="copilot-plan-brainstorm-container"
          >
            <CopilotPlanBrainstormButton
              title={title}
              markdown={markdown}
              copilotApiUrl={copilotApiUrl}
              nameWithOwner={nameWithOwner}
            />
          </div>
        )}
        <Suspense fallback={<ReactionViewerAnchor />}>
          <ReactionViewerRelay subjectId={data.id} canReact={isLoggedIn() && !locked} reactionGroups={dataReaction} />
        </Suspense>
      </div>
    </div>
  )
}
