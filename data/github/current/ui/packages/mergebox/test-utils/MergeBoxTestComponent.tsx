import {AppContext} from '@github-ui/react-core/app-context'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {useMemo} from 'react'

import {MergeMethodContextProvider} from '../contexts/MergeMethodContext'
import {MergeBoxWithSuspense} from '../components/MergeBox'
import {MergeMethod} from '../types'

type MergeBoxTestComponentProps = {
  defaultMergeMethod?: MergeMethod
  hideIcon?: boolean
}

export function MergeBoxTestComponent({defaultMergeMethod = MergeMethod.MERGE, hideIcon}: MergeBoxTestComponentProps) {
  const appPayloadContextValue = useMemo(
    () => ({
      tracing: false,
      tracing_flamegraph: false,
      refListCacheKey: '',
      helpUrl: 'https://docs.github.com',
    }),
    [],
  )

  const appContext = useMemo(() => ({routes: []}), [])

  return (
    <AliveTestProvider>
      <AppContext.Provider value={appContext}>
        <AppPayloadContext.Provider value={appPayloadContextValue}>
          <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
            <MergeMethodContextProvider defaultMergeMethod={defaultMergeMethod}>
              <MergeBoxWithSuspense viewerLogin="monalisa" hideIcon={hideIcon} helpUrl="https://docs.github.com" />
            </MergeMethodContextProvider>
          </PageDataContextProvider>
        </AppPayloadContext.Provider>
      </AppContext.Provider>
    </AliveTestProvider>
  )
}
