import {useChildRouteQuery, useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {LinkButton, PageHeader, PageLayout, UnderlineNav} from '@primer/react'
import {Link, Outlet, useMatch} from 'react-router-dom'

import {reactSandboxFutureDashboardDiscussionsRoute} from './dashboard-discussions-route'
import {reactSandboxFutureDashboardIssuesRoute} from './dashboard-issues-route'
import {reactSandboxFutureDashboardPullsRoute} from './dashboard-pulls-route'
import {reactSandboxFutureDashboardRoute} from './dashboard-route'

export function ReactSandboxFutureDashboard() {
  const {
    data: {user},
  } = useRouteQuery(reactSandboxFutureDashboardRoute, 'mainQuery')
  const {data: deferredData} = useRouteQuery(reactSandboxFutureDashboardRoute, 'deferredPayload')

  const openIssueCount = deferredData?.tabCounts.openIssues
  const openPullCount = deferredData?.tabCounts.openPulls
  const openDiscussionCount = deferredData?.tabCounts.openDiscussions

  const isIssues = useMatch({path: reactSandboxFutureDashboardIssuesRoute.generatePath({}), end: true})
  const isDiscussions = useMatch({path: reactSandboxFutureDashboardDiscussionsRoute.generatePath({}), end: true})
  const isPulls = useMatch({path: reactSandboxFutureDashboardPullsRoute.generatePath({}), end: true})

  return (
    <div data-testid="dashboard-nav">
      <PageLayout>
        <PageLayout.Header>
          <PageHeader aria-label="Dashboard">
            <PageHeader.TitleArea>
              <PageHeader.Title data-hpc>Dashboard for @{user}</PageHeader.Title>
            </PageHeader.TitleArea>
            {isPulls && (
              <PageHeader.Actions>
                <PullsFeedbackButton />
              </PageHeader.Actions>
            )}
            <PageHeader.Navigation>
              <UnderlineNav aria-label="Dashboard">
                <UnderlineNav.Item
                  as={Link}
                  to={reactSandboxFutureDashboardIssuesRoute.generatePath({})}
                  aria-current={isIssues ? 'page' : undefined}
                  counter={openIssueCount}
                >
                  Issues
                </UnderlineNav.Item>
                <UnderlineNav.Item
                  as={Link}
                  to={reactSandboxFutureDashboardPullsRoute.generatePath({})}
                  aria-current={isPulls ? 'page' : undefined}
                  counter={openPullCount}
                >
                  Pulls
                </UnderlineNav.Item>
                <UnderlineNav.Item // this we will want to render based on new feature flag
                  as={Link}
                  to={reactSandboxFutureDashboardDiscussionsRoute.generatePath({})}
                  aria-current={isDiscussions ? 'page' : undefined}
                  counter={openDiscussionCount}
                >
                  Discussions
                </UnderlineNav.Item>
              </UnderlineNav>
            </PageHeader.Navigation>
          </PageHeader>
        </PageLayout.Header>
        <PageLayout.Content as="div">
          <Outlet />
        </PageLayout.Content>
      </PageLayout>
    </div>
  )
}

function PullsFeedbackButton() {
  const {data} = useChildRouteQuery(reactSandboxFutureDashboardPullsRoute, 'mainQuery')
  const url = data?.feedbackUrl

  return <LinkButton href={url}>Feedback</LinkButton>
}
