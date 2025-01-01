import {IssueViewerContextProvider} from '@github-ui/issue-viewer/IssueViewerContextProvider'
import type React from 'react'
import {Suspense} from 'react'
import {NavigationContextProvider} from './contexts/NavigationContext'
import {QueryContextProvider} from './contexts/QueryContext'

type AppProps = {children?: React.ReactNode}

export function App({children}: AppProps) {
  return (
    <NavigationContextProvider>
      <QueryContextProvider>
        <IssueViewerContextProvider>
          <div role="region" id="__primerPortalRoot__" style={{zIndex: 15, position: 'absolute', width: '100%'}} />
          <Suspense fallback={<span>Loading...</span>}>{children}</Suspense>
        </IssueViewerContextProvider>
      </QueryContextProvider>
    </NavigationContextProvider>
  )
}
