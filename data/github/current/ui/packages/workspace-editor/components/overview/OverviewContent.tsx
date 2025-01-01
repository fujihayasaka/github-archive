import {useCurrentRepository} from '@github-ui/current-repository'
import {MarkdownViewer} from '@github-ui/markdown-viewer'
import {branchPath, pullRequestPath} from '@github-ui/paths'
import {useQuery} from '@github-ui/react-query'
import {type SafeHTMLString, SafeHTMLText} from '@github-ui/safe-html'
import {EditorHeader} from '@github-ui/shared-workspace-components/EditorHeader'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {ArrowLeftIcon} from '@primer/octicons-react'
import {BranchName, IssueLabelToken, LabelGroup, Link, Spinner} from '@primer/react'
import {clsx} from 'clsx'

import {useCurrentPullRequest} from '../../contexts/CurrentPullRequestProvider'
import {useDiffCategorization} from '../../hooks/use-diff-categorization'
import type {ConnectedCodespaceData, Label} from '../../utilities/workspace-editor-types'
import styles from './OverviewContent.module.css'
import {OverviewDiffs} from './OverviewDiffs'

type OverviewData = {
  bodyHtml: SafeHTMLString
  titleHtml: SafeHTMLString
  labels: Label[]
}

export interface OverviewContentProps {
  codespaceData: ConnectedCodespaceData
  isTreeExpanded: boolean
  onTerminalClick: () => void
  treeToggleElement: JSX.Element
  onDetailsClick: () => void
}

export function OverviewContent({
  codespaceData,
  isTreeExpanded,
  onTerminalClick,
  onDetailsClick,
  treeToggleElement,
}: OverviewContentProps) {
  const {pullRequest} = useCurrentPullRequest()
  const {baseBranch, headBranch, number} = pullRequest
  const repo = useCurrentRepository()
  const {data: overviewData, isLoading: isOverviewLoading} = useQuery({
    queryKey: ['pull-request', repo.ownerLogin, repo.name, number, 'overview'],
    queryFn: async () => {
      const res = await verifiedFetchJSON(`/${repo.ownerLogin}/${repo.name}/pull/${number}/edit/overview`)
      return (await res.json()) as OverviewData
    },
    meta: {action: 'get-overview'},
  })

  const {data: diffs, isLoading: areDiffsLoading} = useDiffCategorization({analyzeDiffs: true, detectRisk: false})

  if (isOverviewLoading) {
    return (
      <div className="d-flex flex-items-center flex-justify-center mt-4 flex-1">
        <Spinner />
      </div>
    )
  }

  if (!overviewData) return null

  const {bodyHtml, titleHtml, labels = []} = overviewData

  return (
    <>
      <EditorHeader
        key="header-overview"
        initialPath="Overview"
        path="Overview"
        hasCodespaceInfo={!!codespaceData.codespaceInfo}
        codespaceState={codespaceData?.codespaceState}
        codespaceFriendlyName={codespaceData?.codespaceInfo?.environment_data.friendlyName}
        codespaceSkuDisplayName={codespaceData?.codespaceInfo?.environment_data.skuDisplayName}
        codespacePermissionAccepted={!!codespaceData?.permissionsStatus?.accepted}
        codespaceAllowUrl={codespaceData?.permissionsStatus?.allowPermissionsUrl}
        isCodespaceRecoveryContainer={codespaceData.isRecoveryContainer}
        pollForCodespacePermissionsAccepted={codespaceData.pollForPermissionsAccepted}
        recreateCodespace={codespaceData.recreateCodespace}
        isTreeExpanded={isTreeExpanded}
        onTerminalClick={onTerminalClick}
        treeToggleElement={treeToggleElement}
        onDetailsClick={onDetailsClick}
      />
      <div className="d-flex flex-column gap-3 p-3 overflow-y-auto flex-1">
        <div>
          <Link href={pullRequestPath({repo, number: Number(number)})} hoverColor="fg.muted" className="f4">
            <SafeHTMLText className="fgColor-default text-semibold mr-2" html={titleHtml} />
            <span className="fgColor-muted">#{number}</span>
          </Link>
          <div className={clsx('mt-2 d-flex flex-items-center flex-row gap-1 flex-wrap', styles.maxWidthFull)}>
            <BranchName href={branchPath({owner: repo.ownerLogin, repo: repo.name, branch: baseBranch})}>
              {baseBranch}
            </BranchName>
            <ArrowLeftIcon className="color-fg-muted" size={16} />
            <BranchName
              href={branchPath({owner: repo.ownerLogin, repo: repo.name, branch: headBranch})}
              className={clsx(styles.maxWidthFull)}
            >
              {headBranch}
            </BranchName>
          </div>
        </div>
        {labels.length > 0 && (
          <LabelGroup>
            {labels.map((label: Label) => (
              <IssueLabelToken key={label.name} text={label.name} fillColor={`#${label.color}`} />
            ))}
          </LabelGroup>
        )}
        <div className="d-flex flex-column p-3 rounded-2 border">
          {bodyHtml ? (
            <MarkdownViewer verifiedHTML={bodyHtml} />
          ) : (
            <div className="color-fg-muted italic">No description provided.</div>
          )}
        </div>
        <OverviewDiffs diffs={diffs} isLoading={areDiffsLoading} />
      </div>
    </>
  )
}
