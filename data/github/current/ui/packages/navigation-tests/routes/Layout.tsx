import {showRoute} from './show-route'
import {Link, Outlet, useMatch} from 'react-router-dom'
import {memo, type ReactNode} from 'react'
import {CounterLabel, NavList, PageLayout} from '@primer/react'
import {indexRoute} from './index-route'

export const Layout = memo(function Layout() {
  return (
    <PageLayout>
      <PageLayout.Pane position="start">
        <NavList>
          <NavList.Group title="React navigations">
            <NavItem id="react-nav-index" to={indexRoute.generatePath({})}>
              Index
            </NavItem>
            <NavItem id="react-nav-1" to={showRoute.generatePath({id: '1'})}>
              React 1
            </NavItem>
            <NavItem id="react-nav-2" to={showRoute.generatePath({id: '2'})}>
              React 2
            </NavItem>
            <NavItem id="react-nav-3" to={showRoute.generatePath({id: '3'})}>
              React 3
            </NavItem>
            <NavItem id="react-nav-404" to={showRoute.generatePath({id: '404'})}>
              React 404
            </NavItem>
          </NavList.Group>
          <NavList.Group title="Drive navigations">
            <NavItem id="drive-nav-1" href={showRoute.generatePath({id: '4'})}>
              Drive 1
            </NavItem>
            <NavItem id="drive-nav-2" href={showRoute.generatePath({id: '5'})}>
              Drive 2
            </NavItem>
            <NavItem id="drive-nav-3" href={showRoute.generatePath({id: '6'})}>
              Drive 3
            </NavItem>
            <NavItem id="drive-nav-404" href={showRoute.generatePath({id: '404'})}>
              Drive 404
            </NavItem>
            <NavItem id="drive-nav-other" href="/_soft_navigation_tests_other">
              Drive to different React app
            </NavItem>
          </NavList.Group>
        </NavList>
      </PageLayout.Pane>
      <PageLayout.Content as="div">
        <h1>Soft Navigation Tests</h1>
        <div>
          <section>
            <Outlet />
          </section>
        </div>
      </PageLayout.Content>
    </PageLayout>
  )
})

function NavItem({
  href,
  to,
  children,
  count,
  matchPath,
  id,
}:
  | {to: string; children: ReactNode; href?: undefined; count?: number; matchPath?: string; id: string}
  | {href: string; to?: undefined; children: ReactNode; count?: number; matchPath?: string; id: string}) {
  const path = to ?? href
  const isCurrent = useMatch({path: matchPath ?? path, end: !matchPath})
  const ariaCurrent = isCurrent ? 'page' : undefined

  if (href != null) {
    return (
      <NavList.Item href={href} aria-current={ariaCurrent} id={id}>
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
    <NavList.Item as={Link} to={to} aria-current={ariaCurrent} id={id}>
      {children}
      {count !== undefined && (
        <NavList.TrailingVisual>
          <CounterLabel>{count}</CounterLabel>
        </NavList.TrailingVisual>
      )}
    </NavList.Item>
  )
}
