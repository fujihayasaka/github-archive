import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {Link} from '@github-ui/react-core/link'
import {SafeHTMLDiv, type SafeHTMLString} from '@github-ui/safe-html'
import {NavList, PageLayout} from '@primer/react'
import type React from 'react'
import {memo} from 'react'
import {Outlet, useLocation, useMatch, useResolvedPath} from 'react-router-dom'

function NavItem({to, children}: {to: string; children: React.ReactNode}) {
  const resolved = useResolvedPath(to)
  const isCurrent = useMatch({path: resolved.pathname, end: true})
  return (
    <NavList.Item as={Link} to={to} aria-current={isCurrent ? 'page' : undefined}>
      {children}
    </NavList.Item>
  )
}
function NavItemHref({href, children}: {href: string; children: React.ReactNode}) {
  const resolved = useResolvedPath(href)
  const isCurrent = useMatch({path: resolved.pathname, end: true})
  return (
    <NavList.Item href={href} aria-current={isCurrent ? 'page' : undefined}>
      {children}
    </NavList.Item>
  )
}

export function SandboxLayout(
  props:
    | {children: React.ReactNode; serverChildren?: undefined}
    | {serverChildren: SafeHTMLString; children?: undefined},
) {
  return (
    <PageLayout>
      <PageLayout.Pane position="start">
        {/* TODO: Replace with NavigationList when it's ready */}
        <NavList aria-label="Main">
          <NavItem to="/_react_sandbox">Index</NavItem>
          {[
            ['1', 'Show 1'],
            ['2', 'Show 2'],
            ['3', 'Show 3'],
            ['4', 'Show 4 (server 404)'],
            ['5', 'Show 5 (server 500)'],
            ['6', 'Show 6 (render throws)'], // See show.tsx
            ['7', 'Show 7 (redirects to 1)'],
            ['8', 'Show 8 (redirects to /pulls)'],
            ['9', 'Show 9 (selective ssr enabled)'],
            ['10', 'Show 10 (selective ssr disabled)'],
            ['11', 'Show 11 (selective ssr highly cacheable)'],
            ['12', 'Show 12 (selective ssr no js experience)'],
            ['13', 'Show 13 (selective ssr nil hint)'],
            ['14', 'Show 14 (selective ssr empty hint)'],
          ].map(([id, label]) => (
            <NavItem key={id} to={`/_react_sandbox/${id}`}>
              {label}
            </NavItem>
          ))}
          <NavItem to="/_react_sandbox/ssr-error">SSR error</NavItem>
          <NavItemHref href="/_react_sandbox/alloy">Show Alloy (non-React-nav)</NavItemHref>
          <NavItemHref href="/_react_sandbox/lazy">Show Lazy Payload (non-React-nav)</NavItemHref>
          <NavItemHref href="/_react_sandbox/partial">Partial (non-React-nav)</NavItemHref>
          <NavItem to="/_react_sandbox/filter">Filter</NavItem>
          <NavItem to="/_react_sandbox/css-modules">Css Modules</NavItem>
          <NavItem to="/_react_sandbox/relay">Relay Route</NavItem>
          <NavItem to="/_react_sandbox/static-asset">Static Asset</NavItem>
          <NavItem to="/_react_sandbox/ui-deploys">UI Deploys</NavItem>
        </NavList>
      </PageLayout.Pane>
      <PageLayout.Content as="div">
        {props.serverChildren ? <SafeHTMLDiv html={props.serverChildren} /> : props.children}
      </PageLayout.Content>
    </PageLayout>
  )
}

const LocationBasedErrorBoundary = ({children}: {children: React.ReactNode}) => {
  const location = useLocation()
  return <ErrorBoundary key={location.pathname}>{children}</ErrorBoundary>
}

export const SandboxLayoutWithOutlet = memo(function SandboxLayoutWithOutlet() {
  return (
    <SandboxLayout>
      <LocationBasedErrorBoundary>
        <Outlet />
      </LocationBasedErrorBoundary>
    </SandboxLayout>
  )
})
