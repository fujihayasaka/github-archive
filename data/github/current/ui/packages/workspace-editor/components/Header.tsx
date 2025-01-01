import {useCurrentRepository} from '@github-ui/current-repository'
import {ownerPath, pullRequestPath, repositoryPath} from '@github-ui/paths'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useQuery} from '@github-ui/react-query'
import {SafeHTMLBox, type SafeHTMLString} from '@github-ui/safe-html'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {CodeReviewIcon, CopilotIcon, GlobeIcon, MarkGithubIcon, ThreeBarsIcon} from '@primer/octicons-react'
import {Breadcrumbs, Button, IconButton, Link, Stack} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import type React from 'react'
import {memo, useCallback, useState} from 'react'

import {useFilesContext} from '../contexts/FilesContext'
import {useWorkspaceEditorUIDispatch} from '../contexts/WorkspaceEditorUIContext'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'
import {FeedbackLink} from './FeedbackLink'
import styles from './Header.module.css'
import {MessageDialog} from './MessageDialog'

function CommitChangesButton({
  onCommitClick,
  commitButtonRef,
}: {
  onCommitClick?: () => void
  commitButtonRef: React.RefObject<HTMLButtonElement>
}) {
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const {getFileStatuses} = useFilesContext()
  const changedFileCount = Object.values(getFileStatuses()).length
  const hasChanges = changedFileCount > 0
  const tooltipText = hasChanges ? 'Commit changes' : 'No changes to commit.'

  return (
    <>
      <Tooltip text={tooltipText} type="label" ref={commitButtonRef}>
        <Button
          variant="primary"
          aria-disabled={!hasChanges}
          inactive={!hasChanges}
          onClick={hasChanges ? onCommitClick : () => setIsDialogOpen(true)}
          count={hasChanges ? changedFileCount : undefined}
        >
          <span className={styles.commitButtonLabelMobile}>Commit…</span>
          <span className={styles.commitButtonLabel}>Review and commit…</span>
        </Button>
      </Tooltip>
      {isDialogOpen && (
        <MessageDialog
          title="No changes detected"
          message="You don’t have any local changes. Make edits before trying to commit."
          onClose={() => setIsDialogOpen(false)}
          returnFocusRef={commitButtonRef}
        />
      )}
    </>
  )
}

export interface HeaderProps {
  pullRequestNumber: string
  onCommitClick?: () => void
  copilotHeaderButtonRef: React.RefObject<HTMLButtonElement>
  suggestionsHeaderButtonRef?: React.RefObject<HTMLButtonElement>
  actionableSuggestionsCount: number
  commitButtonRef: React.RefObject<HTMLButtonElement>
  forwardedUrl: string | undefined
}

export const GlobalSidePanel = () => {
  const {data, isLoading} = useQuery({
    queryKey: ['side-panels-global'],
    queryFn: async () => {
      const resp = await verifiedFetch('/_side-panels/global')
      return resp.text()
    },
  })

  if (isLoading) {
    return <IconButton aria-label="Open global navigation menu" icon={ThreeBarsIcon} />
  } else {
    return <SafeHTMLBox html={data as SafeHTMLString} />
  }
}

export const Header = memo(function Header({
  pullRequestNumber,
  onCommitClick,
  copilotHeaderButtonRef,
  suggestionsHeaderButtonRef,
  actionableSuggestionsCount,
  commitButtonRef,
  forwardedUrl,
}: HeaderProps) {
  const repo = useCurrentRepository()
  const pullHref = pullRequestPath({repo, number: Number(pullRequestNumber)})
  const repoHref = repositoryPath({owner: repo.ownerLogin, repo: repo.name})
  const ownerHref = ownerPath({owner: repo.ownerLogin})
  const dispatch = useWorkspaceEditorUIDispatch()
  const {copilotAccessAllowed} = useRoutePayload<WorkspaceEditorRoutePayload>()

  const onPanelButtonClick = useCallback(
    (type: RightPanelType, e: React.MouseEvent<HTMLButtonElement>) => {
      dispatch({
        type: 'TOGGLE_RIGHT_PANEL',
        rightPanel: type,
        rightPanelButton: e.currentTarget,
      })
    },
    [dispatch],
  )

  const onCopilotClick = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      onPanelButtonClick(RightPanelType.Chat, e)
    },
    [onPanelButtonClick],
  )

  const onSuggestionsClick = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      onPanelButtonClick(RightPanelType.Suggestions, e)
    },
    [onPanelButtonClick],
  )

  return (
    <Stack direction="horizontal" align="center" wrap="wrap" gap="condensed" justify="space-between" padding="none">
      <Stack direction="horizontal" align="center" wrap="nowrap">
        <Stack direction="horizontal" align="center">
          <GlobalSidePanel />
          <Link aria-label="Homepage" className={styles.homepageLink} href="/">
            <MarkGithubIcon size={32} className={styles.logo} />
          </Link>
          <div className={styles.productName}>Copilot Workspace</div>
        </Stack>

        <Stack direction="horizontal" align="center" wrap="nowrap" className="hide-sm flex-1">
          <Breadcrumbs className={styles.breadcrumbs}>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={ownerHref}>
              {repo.ownerLogin}
            </Breadcrumbs.Item>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={repoHref}>
              {repo.name}
            </Breadcrumbs.Item>
            <Breadcrumbs.Item className={styles.breadcrumbLink} href={pullHref}>
              #{pullRequestNumber}
            </Breadcrumbs.Item>
          </Breadcrumbs>
          <FeedbackLink />
        </Stack>
      </Stack>

      {/* Buttons wrap to second line on narrow viewports */}
      <Stack direction="horizontal" align="center">
        <Stack direction="horizontal" align="center" wrap="nowrap">
          {copilotAccessAllowed && (
            <IconButton
              aria-label="Toggle Copilot panel"
              icon={CopilotIcon}
              onClick={onCopilotClick}
              ref={copilotHeaderButtonRef}
              className="flex-shrink-0"
            />
          )}
          <Button
            onClick={onSuggestionsClick}
            ref={suggestionsHeaderButtonRef}
            count={actionableSuggestionsCount}
            className="hide-xs hide-sm"
          >
            Suggestions
          </Button>
          <IconButton
            onClick={onSuggestionsClick}
            ref={suggestionsHeaderButtonRef}
            aria-label={`${actionableSuggestionsCount} ${
              actionableSuggestionsCount === 1 ? 'suggestion' : 'suggestions'
            }`}
            icon={CodeReviewIcon}
            className="hide-md hide-lg hide-xl"
          />
          {forwardedUrl && (
            <IconButton
              aria-label="Open preview"
              icon={GlobeIcon}
              onClick={() => window.open(forwardedUrl, '_blank')}
            />
          )}
        </Stack>

        {/* Commit button gets pushed to right side when narrow */}
        <CommitChangesButton onCommitClick={onCommitClick} commitButtonRef={commitButtonRef} />
      </Stack>
    </Stack>
  )
})
