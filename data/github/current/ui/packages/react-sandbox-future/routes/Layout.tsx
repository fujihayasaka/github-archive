import {CounterLabel, NavList, PageLayout} from '@primer/react'
import {memo, type ReactNode} from 'react'
import {Link, Outlet, useMatch} from 'react-router-dom'
import {reactSandboxFutureIdRoute} from './id-route'
import {reactSandboxFutureIndexRoute} from './index-route'
import {reactSandboxFutureLayoutRoute} from './layout-route'
import styles from './layout.module.css'
import {DisplayQueries} from '../components/DisplayQueries'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {reactSandboxFutureDashboardIssuesRoute} from './dashboard-issues-route'
import {reactSandboxFutureDashboardRoute} from './dashboard-route'

export const ReactSandboxFutureLayout = memo(function Layout() {
  return (
    <PageLayout>
      <PageLayout.Pane position="start">
        <NavList>
          <NavList.Group title="React navigation">
            <NavItem to={reactSandboxFutureIndexRoute.generatePath({})}>/_react_sandbox_future</NavItem>
            <IdNavItem id="1">/_react_sandbox_future/1</IdNavItem>
            <IdNavItem id="2">/_react_sandbox_future/2</IdNavItem>
            <IdNavItem id="3">404 Error</IdNavItem>
            <NavItem
              to={reactSandboxFutureDashboardIssuesRoute.generatePath({})}
              matchPath={`${reactSandboxFutureDashboardRoute.generatePath({})}/*`}
            >
              Dashboard
            </NavItem>
          </NavList.Group>
          <NavList.Group title="Turbo navigation">
            <NavItem href={reactSandboxFutureIndexRoute.generatePath({})}>/_react_sandbox_future</NavItem>
            <NavItem href={reactSandboxFutureIdRoute.generatePath({id: '1'})}>/_react_sandbox_future/1</NavItem>
            <NavItem href={reactSandboxFutureIdRoute.generatePath({id: '2'})}>/_react_sandbox_future/2</NavItem>
            <NavItem href={reactSandboxFutureIdRoute.generatePath({id: '3'})}>404 Error</NavItem>
            <NavItem
              href={reactSandboxFutureDashboardIssuesRoute.generatePath({})}
              matchPath={`${reactSandboxFutureDashboardRoute.generatePath({})}/*`}
            >
              Dashboard
            </NavItem>
          </NavList.Group>
        </NavList>
      </PageLayout.Pane>
      <PageLayout.Content as="div" className={styles.content}>
        <h1>Data router sandbox</h1>
        <div className={styles['section-content']}>
          <section className={styles.section}>
            Child route data
            <Outlet />
          </section>
        </div>
        <DisplayQueries route={reactSandboxFutureLayoutRoute} />
      </PageLayout.Content>
    </PageLayout>
  )
})

function IdNavItem({id, children}: {id: '1' | '2' | '3'; children: ReactNode}) {
  const {data} = useRouteQuery(reactSandboxFutureLayoutRoute, 'mainQuery')
  const count = data.tabCounts[id]
  return (
    <NavItem to={reactSandboxFutureIdRoute.generatePath({id})} count={count}>
      {children}
    </NavItem>
  )
}

function NavItem({
  href,
  to,
  children,
  count,
  matchPath,
}:
  | {to: string; children: ReactNode; href?: undefined; count?: number; matchPath?: string}
  | {href: string; to?: undefined; children: ReactNode; count?: number; matchPath?: string}) {
  const path = to ?? href
  const isCurrent = useMatch({path: matchPath ?? path, end: !matchPath})
  const ariaCurrent = isCurrent ? 'page' : undefined

  if (href != null) {
    return (
      <NavList.Item href={href} aria-current={ariaCurrent}>
        {children}
        {count !== undefined && (
          <NavList.TrailingVisual>
            <CounterLabel>{count}</CounterLabel>
          </NavList.TrailingVisual>
        )}
      </NavList.Item>
    )
  }

  return (
    <NavList.Item as={Link} to={to} aria-current={ariaCurrent}>
      {children}
      {count !== undefined && (
        <NavList.TrailingVisual>
          <CounterLabel>{count}</CounterLabel>
        </NavList.TrailingVisual>
      )}
    </NavList.Item>
  )
}
