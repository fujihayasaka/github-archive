import {graphql, useFragment} from 'react-relay'
import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import styles from './RepositoryMilestone.module.css'
import {Suspense, useEffect} from 'react'
import {usePreloadedQuery, useQueryLoader, type PreloadedQuery} from 'react-relay/hooks'
import type {RepositoryMilestoneQuery} from './__generated__/RepositoryMilestoneQuery.graphql'
import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'
import {LABELS} from './constants/labels'
import {VALUES} from './constants/values'
import type {RepositoryMilestoneInternal$key} from './__generated__/RepositoryMilestoneInternal.graphql'
import {JobInfoWithSubscription} from '@github-ui/issues-bulk-actions/JobInfoWithSubscription'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {MilestoneError} from './MilestoneError'
import {MilestoneActions} from './MilestoneActions'
import {MilestoneIssuesList} from './MilestoneIssuesList'
import {MilestoneDetail} from './MilestoneDetail'
import {setTitle as setDocumentTitle} from '@github-ui/document-metadata'

export const RepositoryMilestonePageQuery = graphql`
  query RepositoryMilestoneQuery($owner: String!, $name: String!, $number: Int!, $first: Int!, $query: String!) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestoneInternal @arguments(first: $first, number: $number, query: $query)
    }
  }
`

export const RepositoryMilestone = ({queryRef}: {queryRef: PreloadedQuery<RepositoryMilestoneQuery>}) => {
  const [pageQueryRef] = useQueryLoader<RepositoryMilestoneQuery>(RepositoryMilestonePageQuery, queryRef)
  if (!pageQueryRef) return null

  return (
    <Suspense fallback={<div>Loading...</div>}>
      <RepositoryMilestoneContent pageQueryRef={pageQueryRef} />
    </Suspense>
  )
}

function RepositoryMilestoneContent({pageQueryRef}: {pageQueryRef: PreloadedQuery<RepositoryMilestoneQuery>}) {
  const pageData = usePreloadedQuery<RepositoryMilestoneQuery>(RepositoryMilestonePageQuery, pageQueryRef)

  if (!pageData.repository) return null

  return <RepositoryMilestoneInternal repository={pageData.repository} />
}

export function RepositoryMilestoneInternal({
  repository,
  optionConfig,
}: {
  repository: RepositoryMilestoneInternal$key
  optionConfig?: UserSettingsOptionConfig
}) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestoneInternal on Repository
      @argumentDefinitions(first: {type: "Int!"}, number: {type: "Int!"}, query: {type: "String!"}) {
        nameWithOwner
        ...MilestoneActions @arguments(number: $number)
        ...MilestoneIssuesList @arguments(first: $first, number: $number, query: $query)
        milestone(number: $number) {
          ...MilestoneDetail
          title
          number
        }
      }
    `,
    repository,
  )

  const [bulkJobId, setBulkJobId] = useLocalStorage<string | null>(VALUES.localStorageKeyBulkUpdateIssues, null)

  useEffect(() => {
    let pageTitle = 'Milestone'
    if (data.milestone && data.nameWithOwner) {
      pageTitle = `${data.milestone.title} · Milestone #${data.milestone.number} · ${data.nameWithOwner}`
    }
    setDocumentTitle(pageTitle)
  }, [data.milestone, data.nameWithOwner])

  if (!data.milestone) return null

  return (
    <JobInfoWithSubscription bulkJobId={bulkJobId} setBulkJobId={setBulkJobId}>
      <ThreePanesLayout
        contentAs="div"
        resizeable={false}
        leftPaneWidth="small"
        middlePane={
          <div className={styles.middlePaneWrapper}>
            <ErrorBoundary
              fallback={<MilestoneError title={LABELS.milestoneError} message={LABELS.milestoneErrorMessage} />}
            >
              <MilestoneActions repositoryRef={data} optionConfig={optionConfig} />
              <div className={styles.middlePaneGrid}>
                <MilestoneDetail milestoneRef={data.milestone} />
                <ErrorBoundary
                  fallback={
                    <MilestoneError title={LABELS.milestoneIssuesError} message={LABELS.milestoneIssuesErrorMessage} />
                  }
                >
                  <MilestoneIssuesList
                    repositoryRef={data}
                    singleKeyShortcutsEnabled={optionConfig?.singleKeyShortcutsEnabled}
                  />
                </ErrorBoundary>
              </div>
            </ErrorBoundary>
          </div>
        }
      />
    </JobInfoWithSubscription>
  )
}
