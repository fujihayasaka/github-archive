import {GitHubAvatar} from '@github-ui/github-avatar'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useQuery} from '@github-ui/react-query'
import {SearchIcon} from '@primer/octicons-react'
import {FormControl, PageHeader, Stack, TextInput} from '@primer/react'
import {InlineMessage, SkeletonAvatar, SkeletonText} from '@primer/react/experimental'
import {useState} from 'react'
import {useNavigate, useSearchParams} from 'react-router-dom'

import ExampleHeader from '../components/ExampleHeader'
import {IssueTable} from '../components/IssueTable'
import type {Issue} from '../data-types'
import {reactCoreExamplesDependentDataRoute} from './dependent-data-route'

type DeferredIssuesPayload = {
  issues: Issue[]
}

export function ReactCoreExamplesDependentData() {
  const [searchParams] = useSearchParams()
  const {data: user, isPending: isPendingUser} = useRouteQuery(reactCoreExamplesDependentDataRoute, 'mainQuery')
  const [username, setUsername] = useState(user.login ?? searchParams.get('login') ?? '')

  const queryDeps = {
    pathname: `${reactCoreExamplesDependentDataRoute.generatePath({})}/deferred`,
    searchParams: {user_id: user?.id},
  }
  const {data: deferredIssues, isPending: isPendingIssues} = useQuery({
    queryKey: ['react-core-examples', 'dependent-data', 'deferredDependentData', queryDeps],
    queryFn: () => {
      return queryFnFetch<DeferredIssuesPayload>({
        queryDeps,
      })
    },
    enabled: !!user?.id,
  })

  const issues = deferredIssues?.issues || []
  const navigate = useNavigate()

  return (
    <>
      <ExampleHeader
        pageTitle="Dependent Data"
        docsUrl="https://github.com/github/github/blob/master/ui/packages/react-core/future/docs/data-router/recipes/dependent-data.md"
      />
      <FormControl>
        <FormControl.Label id="username-input">Search by username</FormControl.Label>
        <TextInput
          aria-labelledby="username-input"
          onChange={e => setUsername(e.target.value)}
          value={username}
          block
          trailingAction={
            <TextInput.Action
              icon={SearchIcon}
              aria-label="Search"
              onClick={() =>
                navigate(reactCoreExamplesDependentDataRoute.generatePath({}, {search: {login: username}}))
              }
            />
          }
          onKeyDown={e => {
            // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
            if (e.key === 'Enter') {
              navigate(reactCoreExamplesDependentDataRoute.generatePath({}, {search: {login: username}}))
            }
          }}
          loading={isPendingUser}
        />
      </FormControl>

      {!isPendingUser ? (
        user?.login ? (
          <PageHeader aria-label="User">
            <PageHeader.TitleArea variant="medium">
              <PageHeader.LeadingVisual>
                <GitHubAvatar size={30} src={user?.avatarUrl ?? ''} alt={user?.login} />
              </PageHeader.LeadingVisual>
              <PageHeader.Title as="h3">{user?.login}</PageHeader.Title>
            </PageHeader.TitleArea>
          </PageHeader>
        ) : (
          <InlineMessage variant="warning">No user found. Try searching for a different username.</InlineMessage>
        )
      ) : (
        <>
          <Stack direction="horizontal" gap="condensed">
            <SkeletonAvatar size={40} />
            <SkeletonText size="titleMedium" />
          </Stack>
        </>
      )}

      <IssueTable issues={issues} isPending={!!user?.login && isPendingIssues} />
    </>
  )
}
