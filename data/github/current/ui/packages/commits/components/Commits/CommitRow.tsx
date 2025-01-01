import {announce} from '@github-ui/aria-live'
import {CheckStatusDialog, useCommitChecksStatusDetails} from '@github-ui/commit-checks-status'
import type {RepositoryNWO} from '@github-ui/current-repository'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemSafeHTMLTitle, ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {SafeHTMLText} from '@github-ui/safe-html'
import {useAnalytics} from '@github-ui/use-analytics'
import {useClientValue} from '@github-ui/use-client-value'
import {lazy, Suspense, useEffect, useRef, useState} from 'react'

import {useIsLoggingInformationProvided, useLoggingInfo} from '../../contexts/CommitsLoggingContext'
import {useFindDeferredCommitData} from '../../contexts/DeferredCommitDataContext'
import type {Commit, ListCommitMessage} from '../../shared/types'
import {CommitAttribution} from '../CommitAttribution'
import {
  BrowseRepositoryAtThisPoint,
  CommitCommentCount,
  ToggleCommitDescription,
  ViewCodeAtThisPoint,
  ViewCommitDetails,
} from '../CommitRowActions'
import {CommitChecksStatusBadge, SignedCommitBadge} from '../CommitRowBadges'
import {CopySHA} from '../CopySHA'
import styles from './CommitRow.module.css'

export interface CommitRowProps {
  commit: Commit<ListCommitMessage>
  repo: RepositoryNWO
  path: string
  softNavToCommit?: boolean
}

// eslint-disable-next-line github/no-then
const CommitActionBar = lazy(() => import('./CommitActionBar').then(m => ({default: m.CommitActionBar})))

export function CommitRow({commit, repo, path, softNavToCommit}: CommitRowProps) {
  const [showDescription, setShowDescription] = useState(false)
  const commitDescriptionRef = useRef<HTMLSpanElement>(null)
  const [details, fetchDetails] = useCommitChecksStatusDetails(commit.oid, repo)
  const [isOpen, setIsOpen] = useState(false)
  const deferredData = useFindDeferredCommitData(commit.oid)
  const [isSSR] = useClientValue(() => false, true, [])

  const {sendAnalyticsEvent} = useAnalytics()
  const {loggingPrefix, loggingPayload} = useLoggingInfo()
  const shouldLog = useIsLoggingInformationProvided()
  const loggingFunction = () => {
    if (shouldLog) {
      sendAnalyticsEvent(`${loggingPrefix}click`, 'COMMITS_TITLE_CLICKED', loggingPayload)
    }
  }

  useEffect(() => {
    if (showDescription && commitDescriptionRef.current && commitDescriptionRef.current.textContent) {
      announce(commitDescriptionRef.current.textContent)
    }
  }, [commitDescriptionRef, showDescription])

  return (
    <>
      <ListItem
        data-testid="commit-row-item"
        data-commit-link={commit.url}
        title={
          commit.shortMessageMarkdownLink && !isSSR ? (
            <ListItemSafeHTMLTitle
              html={commit.shortMessageMarkdownLink}
              onClick={loggingFunction}
              containerClassName={styles.ListItemTitle_0}
              headingClassName={styles.ListItemTitle_0}
            >
              {commit.bodyMessageHtml && (
                <ToggleCommitDescription
                  showDescription={showDescription}
                  setShowDescription={setShowDescription}
                  oid={commit.oid}
                />
              )}
            </ListItemSafeHTMLTitle>
          ) : (
            <ListItemTitle
              value={commit.shortMessage}
              href={commit.url}
              onClick={loggingFunction}
              containerClassName={styles.ListItemTitle_0}
              headingClassName={styles.ListItemTitle_0}
            >
              {commit.bodyMessageHtml && (
                <ToggleCommitDescription
                  showDescription={showDescription}
                  setShowDescription={setShowDescription}
                  oid={commit.oid}
                />
              )}
            </ListItemTitle>
          )
        }
        metadata={
          <>
            <ListItemMetadata>
              <CommitCommentCount oid={commit.oid} repo={repo} count={deferredData?.commentCount ?? 0} />
            </ListItemMetadata>

            <ListItemMetadata className={styles.ListItemMetadata_0}>
              <SignedCommitBadge deferredData={deferredData} />
            </ListItemMetadata>

            <ListItemMetadata className="d-none d-sm-flex px-0 gap-2" variant="primary">
              <div className="d-flex">
                <ViewCommitDetails oid={commit.oid} commitUrl={commit.url} softNavToCommit={softNavToCommit} />
                <CopySHA sha={commit.oid} />
              </div>
              <ViewCodeAtThisPoint repo={repo} oid={commit.oid} path={path} />
              <BrowseRepositoryAtThisPoint repo={repo} oid={commit.oid} />
            </ListItemMetadata>
          </>
        }
        secondaryActions={
          <Suspense>
            <CommitActionBar
              commit={commit}
              repo={repo}
              path={path}
              setDialogOpen={setIsOpen}
              fetchCheckDetails={fetchDetails}
              deferredData={deferredData}
            />
          </Suspense>
        }
        className={styles.ListItem_0}
      >
        <div className="px-1" />
        <ListItemMainContent>
          {showDescription && commit.bodyMessageHtml && (
            <ListItemDescription>
              <SafeHTMLText
                ref={commitDescriptionRef}
                html={commit.bodyMessageHtml}
                className="ws-pre-wrap extended-commit-description-container pb-2 text-mono wb-break-word"
              />
            </ListItemDescription>
          )}

          <ListItemDescription>
            <CommitAttribution commit={commit} repo={repo}>
              <CommitChecksStatusBadge repository={repo} deferredData={deferredData} oid={commit.oid} />
            </CommitAttribution>
          </ListItemDescription>
        </ListItemMainContent>
      </ListItem>
      {deferredData?.statusCheckStatus && isOpen && (
        <CheckStatusDialog
          combinedStatus={details}
          isOpen={isOpen}
          onDismiss={() => {
            setIsOpen(false)
          }}
        />
      )}
    </>
  )
}
