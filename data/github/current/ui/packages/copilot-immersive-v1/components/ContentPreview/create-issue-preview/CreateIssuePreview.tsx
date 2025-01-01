import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CreateIssueFooter} from '@github-ui/issue-create/CreateIssueFooter'
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import type {OnCreateProps} from '@github-ui/issue-create/Model'
import {IssueViewerLoading} from '@github-ui/issue-viewer/IssueViewerLoading'
import {testIdProps} from '@github-ui/test-id-props'
import {Button, Link, Stack} from '@primer/react'
import {useEffect, useRef, useState, useSyncExternalStore} from 'react'

import {BROWSER_ANIMATION_DURATION} from '../../../utils/constants'
import type {DraftIssue} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'
import {VersionSelector} from '../VersionSelector'
import {CreateIssueButton} from './CreateIssueButton'
import {CreateIssueForm} from './CreateIssueForm'
import styles from './CreateIssuePreview.module.css'
import {RepositoryPicker} from './RepositoryPicker'
import {SubissuesList} from './SubissuesList'
import {TemplatePicker} from './TemplatePicker'
import {useDraftIssueTreeMap} from './use-draft-issue-tree-map'
import {useOnChangeCallback} from './use-on-change-callback'
import {useOnCreateBulkCallback} from './use-on-create-bulk-callback'
import {useOnCreateCallback} from './use-on-create-callback'
import {usePreProcessedNewIssue} from './use-pre-processed-new-issue'
import {useRepoQuery} from './use-repo-query'
import {useTopReposQuery} from './use-top-repos-query'
import {useTransformCopilotImageURLsFunction} from './use-transform-copilot-image-urls-function'

export const METADATA_FOOTER_BREAKPOINT = 1024

export type CreateIssuePreviewProps = {
  issue: DraftIssue
  isPreviewOpening: boolean
  onClose: () => void
}

export function CreateIssuePreview({isPreviewOpening, issue: draftIssue, onClose}: CreateIssuePreviewProps) {
  draftIssue = usePreProcessedNewIssue(draftIssue)
  const {openItem} = useContentPreview()

  const treeNodes = useDraftIssueTreeMap()
  const currentNode = treeNodes.get(draftIssue.tag)
  const isBulkCreate =
    copilotFeatureFlags.draftIssueTree && currentNode?.parent === null && currentNode?.children.length > 0

  // There are rendering issues if we draw the form while animating the workbench opening, so we show loading until the animation is done.
  const [isAnimating, setIsAnimating] = useState(isPreviewOpening)
  useEffect(() => {
    if (isAnimating) {
      const timer = setTimeout(() => setIsAnimating(false), BROWSER_ANIMATION_DURATION)
      return () => clearTimeout(timer)
    }
  }, [isAnimating])

  const {selectedThreadID} = useChatState()

  // Load repositories
  const {isLoading: loadingTopRepos, data: topReposQuery} = useTopReposQuery()
  const [owner, repo] = draftIssue.repository?.split('/') ?? []
  const {isLoading: loadingDraftIssueRepo, data: draftIssueRepo} = useRepoQuery({owner, repo})

  const transformCopilotImageURLs = useTransformCopilotImageURLsFunction(draftIssueRepo)
  const onCreate = useOnCreateCallback(draftIssue)
  const onCreateBulk = useOnCreateBulkCallback(draftIssue)
  const onChange = useOnChangeCallback(draftIssue)

  const containerRef = useRef<HTMLDivElement>(null)
  const renderNarrowView = useRenderNarrowView(containerRef)
  const parentIssueId = currentNode?.parent?.item.id
  const shouldRenderSubIssueIndicator = copilotFeatureFlags.draftIssueTree && parentIssueId !== undefined

  if (isAnimating || loadingTopRepos) {
    return <IssueViewerLoading optionConfig={{useViewportQueries: false}} />
  }

  if (topReposQuery == null && !loadingDraftIssueRepo && draftIssueRepo == null) {
    return <span>No repositories found.</span>
  }

  return (
    <IssueCreateContextProvider
      optionConfig={getSafeConfig({
        storageKeyPrefix: `${draftIssue.id}@${selectedThreadID!}`,
        insidePortal: renderNarrowView,
      })}
      preselectedData={{repository: draftIssueRepo ?? undefined}}
      {...testIdProps('create-issue-preview')}
    >
      <div className={styles.container} ref={containerRef}>
        <div className={styles.toolbar}>
          <div className={shouldRenderSubIssueIndicator ? styles.toolbarLeftWithDivider : styles.toolbarLeft}>
            <VersionSelector item={draftIssue} />
          </div>
          {shouldRenderSubIssueIndicator && (
            <div className={styles.subIssueIndicator}>
              Edit sub-issue of{' '}
              <Button variant="link" className="fgColor-default" onClick={() => openItem(parentIssueId, true)}>
                {currentNode?.parent?.item.name}
              </Button>
            </div>
          )}
          <div className={styles.toolbarActions}>
            <Link href="https://gh.io/copilot-create-issues-feedback" className="mr-2">
              Give feedback
            </Link>
            {copilotFeatureFlags.draftIssueTemplateRequiredIfBlankIssuesDisabled ||
            copilotFeatureFlags.draftIssueTree ? (
              <CreateIssueButton
                issueTemplate={draftIssue.template}
                issueNode={currentNode}
                isBulkCreate={isBulkCreate}
                onClose={onClose}
                onCreateSuccess={({issue}: OnCreateProps) => onCreate?.(issue)}
                onCreateBulkSuccess={onCreateBulk}
              />
            ) : (
              <CreateIssueFooter hideCreateMore className={styles.createIssueFooter} />
            )}
          </div>
        </div>
        <div className={styles.form}>
          <Stack direction={'horizontal'} align={'center'} gap={'condensed'} className="py-2">
            <RepositoryPicker
              draftIssue={draftIssue}
              resolvedDraftIssueRepo={draftIssueRepo}
              loadingDraftIssueRepo={loadingDraftIssueRepo}
              topReposQuery={topReposQuery}
            />
            <TemplatePicker draftIssue={draftIssue} />
          </Stack>
          <CreateIssueForm
            draftIssue={draftIssue}
            onCreate={onCreate}
            onChange={onChange}
            onClose={onClose}
            onBeforeCreate={transformCopilotImageURLs}
          />
          <SubissuesList issue={draftIssue} />
        </div>
      </div>
    </IssueCreateContextProvider>
  )
}

function useRenderNarrowView<T extends HTMLElement>(elementRef: React.RefObject<T>) {
  const subscribe = (notify: () => void) => {
    const resizeObserver = new ResizeObserver(notify)
    resizeObserver.observe(document.documentElement)
    return () => {
      resizeObserver.unobserve(document.documentElement)
      resizeObserver.disconnect()
    }
  }

  const onChange = () => {
    if (!elementRef.current) return true

    return elementRef.current.clientWidth < METADATA_FOOTER_BREAKPOINT
  }

  return useSyncExternalStore(subscribe, onChange)
}
