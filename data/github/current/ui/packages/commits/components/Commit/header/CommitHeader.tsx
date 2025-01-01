import type {RepositoryNWO} from '@github-ui/current-repository'
import {commitPath, repositoryTreePath} from '@github-ui/paths'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {SafeHTMLText} from '@github-ui/safe-html'
import {SignedCommitBadge} from '@github-ui/signed-commit-badge'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {FileCodeIcon} from '@primer/octicons-react'
import {Button, IconButton, Label, Link as PrimerLink, PageHeader} from '@primer/react'
import {Tooltip} from '@primer/react/deprecated'
import {clsx} from 'clsx'
import {memo, useRef} from 'react'

import {useCommitsAppPayload} from '../../../hooks/use-commits-app-payload'
import type {BranchCommitState} from '../../../hooks/use-load-branch-commits'
import {useLoadSingleDeferredCommitData} from '../../../shared/use-load-deferred-commit-data'
import type {CommitExtended} from '../../../types/commit-types'
import type {DeferredCommitData} from '../../../types/commits-types'
import {shortSha} from '../../../utils/short-sha'
import {AsyncChecksStatusBadge} from '../../AsyncChecksStatusBadge'
import {CommitAttribution} from '../../CommitAttribution'
import {CopySHA} from '../../CopySHA'
import {Panel} from '../../Panel'
import {CommitBranchInfo} from './CommitBranchInfo'
import styles from './CommitHeader.module.css'
import {CommitParents} from './CommitParents'
import {CommitTagInfo} from './CommitTagInfo'

interface CommitHeaderProps {
  commit: CommitExtended
  commitInfo: BranchCommitState
  repo: RepositoryNWO
}

export const CommitHeader = memo(CommitHeaderUnmemoized)

function CommitHeaderUnmemoized({commit, commitInfo, repo}: CommitHeaderProps) {
  const commitSubjectRef = useRef<HTMLSpanElement>(null)
  const deferredData = useLoadSingleDeferredCommitData(
    `${commitPath({owner: repo.ownerLogin, repo: repo.name, commitish: commit.oid})}/deferred_commit_data`,
  )

  return (
    <PageHeader>
      <PageHeader.TitleArea variant="large" sx={{minWidth: 0, alignItems: 'center'}}>
        <PageHeader.Title as="h1" sx={{minWidth: 0}} className="f2">
          Commit <span className="text-mono bgColor-muted rounded p-1">{shortSha(commit.oid)}</span>
        </PageHeader.Title>
      </PageHeader.TitleArea>
      <PageHeader.Actions className={clsx(styles['commit-header-actions'])}>
        <div className="d-flex gap-2 flex-items-center flex-md-justify-end">
          <Feedback />

          <Tooltip
            text="Browse the repository at this point in the history"
            direction="sw"
            sx={{display: 'flex'}}
            className="d-none d-md-flex"
          >
            <Button
              as={PrimerLink}
              sx={{color: 'fg.default'}}
              href={repositoryTreePath({repo, action: 'tree', commitish: commit.oid})}
              leadingVisual={FileCodeIcon}
            >
              Browse files
            </Button>
          </Tooltip>

          <IconButton
            as={PrimerLink}
            href={repositoryTreePath({repo, action: 'tree', commitish: commit.oid})}
            icon={FileCodeIcon}
            aria-label="Browse files"
            className="d-flex d-md-none"
          />
        </div>
      </PageHeader.Actions>
      <PageHeader.Description>
        <div className="d-flex flex-column gap-2 width-full">
          <CommitAttribution
            commit={commit}
            repo={repo}
            settings={{fontColor: 'fg.default', avatarSize: 20, fontWeight: 'bold'}}
            textVariant="muted"
          >
            <DeferredCommitHeaderData deferredData={deferredData} oid={commit.oid} repo={repo} />
          </CommitAttribution>

          <Panel className="pt-0">
            {(commit.shortMessageMarkdown || commit.bodyMessageHtml) && (
              <div className={clsx(styles['commit-message-container'])}>
                {commit.shortMessageMarkdown && (
                  <SafeHTMLText
                    ref={commitSubjectRef}
                    html={commit.shortMessageMarkdown}
                    className="ws-pre-wrap f5 wb-break-word text-mono"
                  />
                )}
                {commit.bodyMessageHtml && (
                  <SafeHTMLText
                    html={commit.bodyMessageHtml}
                    className="ws-pre-wrap extended-commit-description-container f6 wb-break-word text-mono mt-2"
                  />
                )}
              </div>
            )}

            <div className="p-2 d-flex gap-2 flex-column flex-md-row flex-justify-between">
              <div className="d-flex flex-row flex-items-center">
                <CommitBranchInfo data={commitInfo} repo={repo} />
                {commitInfo.tags.length > 0 && <span className="px-2">&middot;</span>}
                <CommitTagInfo data={commitInfo} repo={repo} />
              </div>

              <pre className="color-fg-muted d-flex flex-items-center">
                <CommitParents commit={commit} repo={repo} />
                {' commit '}
                <span className="fgColor-default">{shortSha(commit.oid)}</span>
                <CopySHA sha={commit.oid} direction="sw" />
              </pre>
            </div>
          </Panel>
        </div>
      </PageHeader.Description>
    </PageHeader>
  )
}

function DeferredCommitHeaderData({
  deferredData,
  oid,
  repo,
}: {
  deferredData: DeferredCommitData | undefined
  oid: CommitExtended['oid']
  repo: RepositoryNWO
}) {
  const {helpUrl} = useCommitsAppPayload()
  const isLoading = deferredData === undefined

  let checkStatusCount = ''
  try {
    checkStatusCount = deferredData?.statusCheckStatus?.short_text?.split('checks')[0]?.trim() || ''
  } catch {
    //noop
  }

  return (
    <>
      {isLoading && <LoadingSkeleton className="ml-2" variant="rounded" width={'62px'} />}
      {deferredData?.statusCheckStatus && (
        <>
          <span className="d-flex ml-2 mr-1">&middot;</span>
          <AsyncChecksStatusBadge
            oid={oid}
            status={deferredData?.statusCheckStatus?.state}
            descriptionString={checkStatusCount}
            repo={repo}
          />

          {deferredData?.signatureInformation && deferredData?.verifiedStatus !== 'unsigned' && (
            <span className="d-flex ml-2">&middot;</span>
          )}
        </>
      )}
      {deferredData?.signatureInformation && (
        <div className="ml-2">
          <SignedCommitBadge
            commitOid={oid}
            hasSignature
            verificationStatus={deferredData.verifiedStatus}
            signature={{helpUrl, ...deferredData.signatureInformation}}
          />
        </div>
      )}
    </>
  )
}

function Feedback() {
  const diffUXRefreshBeta = useFeatureFlag('diff_ux_refresh_beta')

  if (!diffUXRefreshBeta) {
    return null
  }

  return (
    <div className="d-flex flex-items-center gap-2">
      <Label variant="success">Preview</Label>
      <PrimerLink
        href="https://gh.io/new-commit-details-feedback"
        target="_blank"
        rel="noopener noreferrer"
        className="no-wrap f5 text-normal d-none d-sm-block"
      >
        Give feedback
      </PrimerLink>
    </div>
  )
}
