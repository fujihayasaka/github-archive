import {useReportErrorContext} from '@github-ui/react-core/future/report-error-context'
import {PageLayout, UnderlineNav} from '@primer/react'
import {useEffect} from 'react'
import {Link, Outlet, useMatch, useRouteError} from 'react-router-dom'

import {reactCoreExamplesNestedLoaderErrorRoute, reactCoreExamplesNestedRenderErrorRoute} from './nested-error-routes'

function UnderlineNavItem<Route extends {path: string; generatePath: (params: Record<string, string>) => string}>({
  route,
  children,
}: {
  route: Route
  params: Parameters<Route['generatePath']>[0]
  children: string
}) {
  const isCurrent = useMatch({path: route.path, end: true})
  return (
    <UnderlineNav.Item as={Link} aria-current={isCurrent ? 'page' : undefined} to={route.generatePath({})}>
      {children}
    </UnderlineNav.Item>
  )
}

export function NestedErrorLayout() {
  return (
    <PageLayout data-hpc>
      <PageLayout.Header>
        <UnderlineNav aria-label="Navigation between nested error routes">
          <UnderlineNavItem route={reactCoreExamplesNestedRenderErrorRoute} params={{}}>
            Render Error
          </UnderlineNavItem>
          <UnderlineNavItem route={reactCoreExamplesNestedLoaderErrorRoute} params={{}}>
            Loader Error
          </UnderlineNavItem>
        </UnderlineNav>
      </PageLayout.Header>
      <PageLayout.Content as="div">
        <Outlet />
      </PageLayout.Content>
    </PageLayout>
  )
}

export function NestedLoaderError() {
  return <p>Loader Error</p>
}

export function NestedRenderError(): JSX.Element {
  throw new Error('This is a test error')
}

function NestedErrorBoundary({type}: {type: string}) {
  const error = useRouteError()
  const reportError = useReportErrorContext()

  useEffect(() => {
    reportError(error)
  }, [error, reportError])

  return (
    <div>
      <h2>{`Nested Error Boundary - ${type}`}</h2>
      <p>This is a test error boundary</p>
    </div>
  )
}

export function NestedRenderErrorBoundary() {
  return <NestedErrorBoundary type="Render Error" />
}
export function NestedLoaderErrorBoundary() {
  return <NestedErrorBoundary type="Loader Error" />
}
