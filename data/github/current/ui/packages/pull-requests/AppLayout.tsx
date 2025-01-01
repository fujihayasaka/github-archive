import type React from 'react'

import {useRouteHeaderData} from './hooks/use-route-header-data'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {useStickyHeader} from '@github-ui/use-sticky-header/useStickyHeader'
import {
  condensedResponsiveWrapperClasses,
  fullWidthResponsiveWrapperClasses,
  StickyPullRequestHeader,
} from './components/StickyPullRequestHeader'
import {SplitPageLayout, type SplitPageLayoutHeaderProps} from '@primer/react'
import {LivePullRequestHeader} from './components/PullRequestHeader'
import {ObservableBox as StickyHeaderActivationThreshold} from '@github-ui/use-sticky-header/ObservableBox'
import type {PropsWithChildren} from 'react'
import {useMatch} from 'react-router-dom'
import {FilesRoutePath} from './routes/route-paths'

// AppLayout is an alias for the SlottedAppLayout component
// It exists for improved readability for Commits JSON route + tests
export function AppLayout(props: {children?: React.ReactNode}) {
  return <SlottedAppLayout>{props.children}</SlottedAppLayout>
}

type SlottedLayoutProps = {
  headerDivider?: SplitPageLayoutHeaderProps['divider']
  renderDefaultStickyHeader?: boolean
}

/**
 * SlottedLayout is a layout component that allows customizing the header and sticky header.
 * This component lets us compose the layout in the route instead of inheriting from the base layout.
 * Any use of this component assumes that you're on the Files route.
 * This layout component is somewhat compatible for use with Data Router.
 */
export function SlottedAppLayout({
  children,
  headerDivider = 'none',
  renderDefaultStickyHeader,
}: PropsWithChildren<SlottedLayoutProps>) {
  const {aliveChannel, pullRequest, bannersData, repository, urls, user} = useRouteHeaderData()
  const {isSticky, observe, unobserve} = useStickyHeader()

  const isFilesRoute = useMatch(`${FilesRoutePath}/*`) !== null
  const responsiveWrapperClasses = isFilesRoute ? fullWidthResponsiveWrapperClasses : condensedResponsiveWrapperClasses

  return (
    <PageDataContextProvider basePageDataUrl={urls.conversation}>
      {renderDefaultStickyHeader && isSticky && (
        <StickyPullRequestHeader
          repository={repository}
          pullRequest={pullRequest}
          responsiveWrapperClasses={responsiveWrapperClasses}
        />
      )}
      <div className={`mt-4 ${responsiveWrapperClasses}`}>
        <SplitPageLayout>
          <SplitPageLayout.Header divider={headerDivider} padding="none">
            <LivePullRequestHeader
              aliveChannel={aliveChannel}
              bannersData={bannersData}
              isFilesRoute={isFilesRoute}
              repository={repository}
              pullRequest={pullRequest}
              urls={urls}
              user={user}
            />
            {renderDefaultStickyHeader && (
              <StickyHeaderActivationThreshold
                sx={{visibility: 'hidden', height: '1px'}}
                onObserve={observe}
                onUnobserve={unobserve}
              />
            )}
          </SplitPageLayout.Header>
          {children}
        </SplitPageLayout>
      </div>
    </PageDataContextProvider>
  )
}
