import {Suspense, useState} from 'react'

import {Button, PageHeader} from '@primer/react'
import {useHeaderPageData} from '../page-data/loaders/use-header-page-data'
import {PullRequestBanners} from './PullRequestBanners'
import {PullRequestHeaderSummary} from './PullRequestHeaderSummary'
import {PullRequestEditTitleForm} from './PullRequestEditTitleForm'
import {PullRequestStateLabel} from './PullRequestStateLabel'
import type {HeaderPageData} from '../page-data/payloads/header'
import {PullRequestHeaderNavigation} from './PullRequestHeaderNavigation'
import {SafeHTMLText} from '@github-ui/safe-html'
import {useHeaderLiveUpdates} from '../hooks/use-header-live-updates'
import {PullRequestCodeButton} from './PullRequestCodeButton'
import {DiffStat} from './DiffStat'
import {clsx} from 'clsx'
import styles from './PullRequestHeader.module.css'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'

export type PullRequestHeaderProps = HeaderPageData

/**
 * LivePullRequestHeader is a thin wrapper around PullRequestHeader that will automatically update the header when the
 * alive channel is triggered with `{title_updated: true}`. This lives here instead of the base page so that
 * it doesn't re-render the entire page when the title is updated.
 */
export function LivePullRequestHeader({
  bannersData,
  pullRequest,
  repository,
  urls,
  user,
  aliveChannel,
}: PullRequestHeaderProps & {aliveChannel: string}) {
  const {data: headerData} = useHeaderPageData({aliveChannel, repository, pullRequest, bannersData, urls, user})
  useHeaderLiveUpdates(aliveChannel)

  return <PullRequestHeader {...headerData} />
}

export function PullRequestHeader({bannersData, pullRequest, repository, urls, user}: PullRequestHeaderProps) {
  const [isEditing, setIsEditing] = useState(false)

  const titleActions = (
    <>
      {user.canEditTitle && (
        <Button onClick={() => setIsEditing(true)} size="small">
          Edit
        </Button>
      )}
      <PullRequestCodeButton
        codespacesEnabled={repository.codespacesEnabled}
        copilotEnabled={repository.copilotEnabled}
        headBranch={pullRequest.headBranch}
        isEnterprise={repository.isEnterprise}
        pullRequestNumber={pullRequest.number}
        repository={repository}
      />
    </>
  )

  return (
    <>
      {isEditing && (
        <PullRequestEditTitleForm
          initialTitle={pullRequest.title}
          pullRequestNumber={pullRequest.number}
          onCloseForm={() => setIsEditing(false)}
        />
      )}
      {/* This is a hack to make the title actions appear above the title on mobile */}
      {!isEditing && (
        <div className="d-block d-sm-none pb-2 mb-3 flex-md-order-1 flex-shrink-0 d-flex flex-items-center gap-1">
          {titleActions}
        </div>
      )}
      <PageHeader className="flex-items-center">
        {isEditing && (
          // this is done so that we still have an h1 element present when editing the title
          <h1 className="sr-only">{`${pullRequest.title} - #${pullRequest.number}`}</h1>
        )}
        {!isEditing && (
          <>
            <PageHeader.TitleArea>
              <PageHeader.Title as="h1" className="lh-condensed">
                <SafeHTMLText className="f1 text-normal markdown-title" html={pullRequest.titleHtml} />
                <span className="pl-2 fgColor-muted f1-light d-inline">#{pullRequest.number}</span>
              </PageHeader.Title>
            </PageHeader.TitleArea>
            <PageHeader.Actions className="d-none d-sm-flex flex-items-center gap-1">{titleActions}</PageHeader.Actions>
          </>
        )}
        <PageHeader.Description className="d-flex flex-column flex-items-start">
          <div className="d-flex flex-column flex-sm-row gap-2 width-full flex-items-start flex-justify-between">
            <PullRequestStateLabel state={pullRequest.state} />
            <div className="flex-1">
              <PullRequestHeaderSummary
                author={pullRequest.author.login}
                mergedTime={pullRequest.mergedTime}
                baseBranch={pullRequest.baseBranch}
                baseRepositoryDefaultBranch={repository.defaultBranch}
                baseRepositoryName={repository.name}
                baseRepositoryOwnerLogin={repository.ownerLogin}
                canChangeBase={user.canChangeBase}
                commitsCount={pullRequest.commitsCount}
                headBranch={pullRequest.headBranch}
                headRepositoryOwnerLogin={pullRequest.headRepositoryOwnerLogin}
                headRepositoryName={pullRequest.headRepositoryName}
                isInAdvisoryRepo={pullRequest.isInAdvisoryRepo}
                isEditing={isEditing}
                mergedBy={pullRequest.mergedBy}
                setIsEditing={setIsEditing}
                state={pullRequest.state}
              />
            </div>
          </div>
          <PullRequestBanners bannersData={bannersData} pullRequest={pullRequest} repository={repository} />
        </PageHeader.Description>
        <PageHeader.Navigation className="pt-3 px-3 ml-n3 mr-n3">
          <div className={clsx(styles.diffStatesWrapper, 'float-right d-none d-md-block')}>
            <Suspense fallback={<LoadingSkeleton width="80px" />}>
              <DiffStat />
            </Suspense>
          </div>
          <div className="flex-auto">
            <PullRequestHeaderNavigation commitsCount={pullRequest.commitsCount} urls={urls} />
          </div>
        </PageHeader.Navigation>
      </PageHeader>
    </>
  )
}
