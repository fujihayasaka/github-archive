import {ListView} from '@github-ui/list-view'
import {ListViewMetadata} from '@github-ui/list-view/ListViewMetadata'
import {useQueries} from '@github-ui/react-query'
import {useClickAnalytics} from '@github-ui/use-analytics'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {Label, Link, Spinner, Stack} from '@primer/react'
import {Blankslate} from '@primer/react/experimental'
import {useCallback, useState} from 'react'
import styles from '../DashboardLists.module.css'
import type {DashboardPullRequest} from '../types'
import {PullRequestQueryQualifier} from '../types'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {PullRequestListItem} from './PullRequestListItem'
import {PullRequestActionMenu} from './PullRequestActionMenu'
import {dashboardLocalStorage} from '../utils/dashboard-local-storage'

interface PullRequestsListProps {
  userDisplayLogin: string
}

const DEFAULT_RESULT_COUNT = 6
const DEFAULT_QUERY_QUALIFIERS = [PullRequestQueryQualifier.Authored]

export function dedupeById<T extends {id: string | number}>(items: T[]): T[] {
  const seen = new Set<string | number>()
  return items.filter(item => (seen.has(item.id) ? false : seen.add(item.id)))
}

export function PullRequestsList({userDisplayLogin}: PullRequestsListProps) {
  const initialQueryQualifiers = dashboardLocalStorage.getQueryQualifiers() || DEFAULT_QUERY_QUALIFIERS
  const [queryQualifiers, setQueryQualifiers] = useState<PullRequestQueryQualifier[]>(initialQueryQualifiers)
  const initialResultCount = dashboardLocalStorage.getPullRequestResultCount() || DEFAULT_RESULT_COUNT
  const [resultCount, setResultCount] = useState<number>(initialResultCount)

  const setPullRequestQueryQualifiers = (queries: PullRequestQueryQualifier[]) => {
    setQueryQualifiers(queries)
    dashboardLocalStorage.setQueryQualifiers(queries)
  }

  const setPullRequestResultCount = (count: number) => {
    setResultCount(count)
    dashboardLocalStorage.setPullRequestResultCount(count)
  }

  const {sendClickAnalyticsEvent} = useClickAnalytics()
  const onViewAllPulls = useCallback(() => {
    sendClickAnalyticsEvent({category: 'productivity_dashboard', action: 'click.view_all_pulls'})
  }, [sendClickAnalyticsEvent])
  const onTitleClick = useCallback(() => {
    sendClickAnalyticsEvent({category: 'productivity_dashboard', action: 'click.navigate_to_pr'})
  }, [sendClickAnalyticsEvent])
  const baseQuery = 'is:pr is:open archived:false sort:updated-desc'

  const {
    isLoading,
    data: pullRequests,
    isError,
  } = useQueries({
    queries: queryQualifiers.map(qualifier => ({
      queryKey: [baseQuery, qualifier, userDisplayLogin],
      queryFn: async () => {
        const response = await reactFetchJSON(
          `/pulls?q=${encodeURIComponent(`${baseQuery} ${qualifier}:${userDisplayLogin}`)}`,
        )

        if (!response.ok) throw new Error(`HTTP ${response.status}`)

        const payload = (await response.json()).data as DashboardPullRequest[]
        return payload
      },
    })),
    combine: results => {
      return {
        data: dedupeById(results.flatMap(result => result.data || [])).slice(0, resultCount),
        isLoading: results.some(result => result.isLoading),
        isError: results.some(result => result.isError),
      }
    },
  })

  if (isLoading) {
    return (
      <div className={styles.spinnerContainer} data-testid="pull-requests-list-loading">
        <Spinner />
      </div>
    )
  }

  if (isError) {
    return (
      <Blankslate>
        <Blankslate.Heading>Something went wrong</Blankslate.Heading>
        <Blankslate.Description>Failed to load pull requests</Blankslate.Description>
      </Blankslate>
    )
  }

  if (pullRequests) {
    return (
      <ListView
        title="Pull Requests"
        className={styles.List}
        metadata={
          <ListViewMetadata
            className={styles.metadataOverride}
            title={
              <Stack direction="horizontal" gap="condensed" align="center">
                <Link className={styles.titleLink} href="/pulls" onClick={onViewAllPulls}>
                  Pull requests
                </Link>
                <Label variant="secondary">Private preview</Label>
              </Stack>
            }
          >
            <PullRequestActionMenu
              setPullRequestQueryQualifiers={setPullRequestQueryQualifiers}
              selectedPullRequestQueryQualifiers={queryQualifiers}
              setPullRequestResultCount={setPullRequestResultCount}
              initialResultCount={resultCount}
            />
          </ListViewMetadata>
        }
      >
        {pullRequests.length === 0 ? (
          <ListItem title={<ListItemTitle containerClassName={styles.noItems} value="No pull requests" />} />
        ) : (
          pullRequests.map(pullRequest => (
            <PullRequestListItem key={pullRequest.id} pullRequest={pullRequest} onTitleClick={onTitleClick} />
          ))
        )}
      </ListView>
    )
  }
}
