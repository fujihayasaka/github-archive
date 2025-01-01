import type React from 'react'

import {useRouteHeaderData} from './hooks/use-route-header-data'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {PullRequestErrorState} from './components/PullRequestErrorState'
import {useStickyHeader} from '@github-ui/use-sticky-header/useStickyHeader'
import {
  condensedResponsiveWrapperClasses,
  fullWidthResponsiveWrapperClasses,
  StickyPullRequestHeader,
} from './components/StickyPullRequestHeader'
import {SplitPageLayout} from '@primer/react'
import {LivePullRequestHeader} from './components/PullRequestHeader'
import {ObservableBox as StickyHeaderActivationThreshold} from '@github-ui/use-sticky-header/ObservableBox'
import type {PropsWithChildren} from 'react'
import type {HeaderPageData} from './page-data/payloads/header'
import {useMatch} from 'react-router-dom'
import {FilesRoutePath} from './routes/route-paths'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  return (
    <ErrorBoundary critical fallback={<PullRequestErrorState />}>
      <Layout>{props.children}</Layout>
    </ErrorBoundary>
  )
}

function Layout(props: {children?: React.ReactNode}) {
  const {aliveChannel, pullRequest, bannersData, repository, urls, user} = useRouteHeaderData()

  return (
    <LayoutComponent
      aliveChannel={aliveChannel}
      pullRequest={pullRequest}
      bannersData={bannersData}
      repository={repository}
      urls={urls}
      user={user}
    >
      {props.children}
    </LayoutComponent>
  )
}

export function LayoutComponent({
  aliveChannel,
  pullRequest,
  bannersData,
  repository,
  urls,
  user,
  children,
}: PropsWithChildren<HeaderPageData>) {
  const {isSticky, observe, unobserve} = useStickyHeader()
  const isFilesRoute = useMatch(`${FilesRoutePath}/*`)

  const responsiveWrapperClasses = isFilesRoute ? fullWidthResponsiveWrapperClasses : condensedResponsiveWrapperClasses

  return (
    <PageDataContextProvider basePageDataUrl={urls.conversation}>
      {isSticky && (
        <StickyPullRequestHeader
          repository={repository}
          pullRequest={pullRequest}
          responsiveWrapperClasses={responsiveWrapperClasses}
        />
      )}
      <div className={`mt-4 ${responsiveWrapperClasses}`}>
        <SplitPageLayout>
          <SplitPageLayout.Header divider="none" padding="none" className="mb-3">
            <LivePullRequestHeader
              aliveChannel={aliveChannel}
              repository={repository}
              pullRequest={pullRequest}
              bannersData={bannersData}
              urls={urls}
              user={user}
            />
            {/* On scroll, when this element reaches the top of the viewport, the sticky header activates */}
            <StickyHeaderActivationThreshold
              sx={{visibility: 'hidden', height: '1px'}}
              onObserve={observe}
              onUnobserve={unobserve}
            />
          </SplitPageLayout.Header>
          {children}
        </SplitPageLayout>
      </div>
    </PageDataContextProvider>
  )
}
