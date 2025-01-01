import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {NavList, PageLayout, Stack} from '@primer/react'
import type {ReactNode} from 'react'
import {Link, Outlet, useMatch} from 'react-router-dom'

import {reactCoreExamplesDependentDataRoute} from './dependent-data-route'
import {reactCoreExamplesEnrichedDataRoute} from './enriched-data-route'
import {reactCoreExamplesFeatureFlagRoute} from './feature-flag-route'
import {reactCoreExamplesIndexRoute} from './index-route'
import {reactCoreExamplesLayoutRoute} from './layout-route'
import {reactCoreExamplesLiveDataRoute} from './live-data-route'
import {reactCoreExamplesMutationsRoute} from './mutations-route'
import {reactCoreExamplesNestedRenderErrorRoute} from './nested-error-routes'
import {reactCoreExamplesPaginationRoute} from './pagination-route'
import {reactCoreExamplesSharedComponentsRoute} from './shared-components-route'

export const ReactCoreExamplesLayout: React.FC = () => {
  const {
    data: {login},
  } = useRouteQuery(reactCoreExamplesLayoutRoute, 'mainQuery')
  const showFeatureFlag = useFeatureFlag('react_core_examples_feature_flag')

  return (
    <PageLayout>
      <PageLayout.Pane position="start">
        <NavList>
          <NavItem to={reactCoreExamplesIndexRoute.generatePath({})}>Index</NavItem>
          <NavItem
            to={reactCoreExamplesDependentDataRoute.generatePath({}, {search: {login}})}
            matchPath={reactCoreExamplesDependentDataRoute.generatePath({})}
          >
            Dependent Data
          </NavItem>
          <NavItem to={reactCoreExamplesEnrichedDataRoute.generatePath({})}>Enriched Data</NavItem>
          {/* This route is enabled conditionally and has a link in component to disabled it */}
          {showFeatureFlag && (
            <NavItem
              to={reactCoreExamplesFeatureFlagRoute.generatePath(
                {},
                {search: '_features=react_core_examples_feature_flag'},
              )}
              matchPath={reactCoreExamplesFeatureFlagRoute.generatePath({})}
            >
              Feature Flag (enabled)
            </NavItem>
          )}
          {!showFeatureFlag && (
            <NavItem
              to={reactCoreExamplesFeatureFlagRoute.generatePath(
                {},
                {search: '_features=!react_core_examples_feature_flag'},
              )}
              matchPath={reactCoreExamplesFeatureFlagRoute.generatePath({})}
            >
              Feature Flag (disabled)
            </NavItem>
          )}
          <NavItem to={reactCoreExamplesLiveDataRoute.generatePath({})}>Live Data</NavItem>
          <NavItem to={reactCoreExamplesMutationsRoute.generatePath({})}>Mutations</NavItem>
          <NavItem to={reactCoreExamplesPaginationRoute.generatePath({})}>Pagination</NavItem>
          <NavItem to={reactCoreExamplesSharedComponentsRoute.generatePath({})}>Shared Components</NavItem>
          <NavItem to={reactCoreExamplesNestedRenderErrorRoute.generatePath({})}>Nested error</NavItem>
        </NavList>
      </PageLayout.Pane>
      <PageLayout.Content as="div">
        <Stack padding="normal" gap="spacious">
          <Outlet />
        </Stack>
      </PageLayout.Content>
    </PageLayout>
  )
}

function NavItem({to, children, matchPath}: {to: string; children: ReactNode; count?: number; matchPath?: string}) {
  const isCurrent = useMatch({path: matchPath ?? to, end: !matchPath})
  const ariaCurrent = isCurrent ? 'page' : undefined

  return (
    <NavList.Item as={Link} to={to} aria-current={ariaCurrent}>
      {children}
    </NavList.Item>
  )
}
