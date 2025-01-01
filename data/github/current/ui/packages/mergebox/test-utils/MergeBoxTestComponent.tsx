import {RoutesContext} from '@github-ui/react-core/routes-context'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import {useMemo} from 'react'
import type {EnabledFeatures} from '@github-ui/react-core/use-feature-flag'

import {MergeMethodContextProvider} from '../contexts/MergeMethodContext'
import {MergeBoxWithSuspense} from '../components/MergeBox'
import {MergeMethod} from '../types'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import {aliveChannels} from './mocks/alive-channels-mock'

type MergeBoxTestComponentProps = {
  defaultMergeMethod?: MergeMethod
  hideIcon?: boolean
  enabledFeatures?: EnabledFeatures
}

export function MergeBoxTestComponent({
  defaultMergeMethod = MergeMethod.MERGE,
  hideIcon,
  enabledFeatures,
}: MergeBoxTestComponentProps) {
  const appPayloadContextValue = useMemo(
    () => ({
      tracing: false,
      tracing_flamegraph: false,
      refListCacheKey: '',
      helpUrl: 'https://docs.github.com',
    }),
    [],
  )

  const routesContext = useMemo(() => ({routes: []}), [])

  return (
    <AliveTestProvider>
      <RoutesContext.Provider value={routesContext}>
        <AppPayloadContext.Provider value={appPayloadContextValue}>
          <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
            <FeatureFlagProvider features={enabledFeatures ?? {}}>
              <MergeMethodContextProvider defaultMergeMethod={defaultMergeMethod}>
                <MergeBoxWithSuspense
                  viewerLogin="monalisa"
                  hideIcon={hideIcon}
                  helpUrl="https://docs.github.com"
                  channels={aliveChannels}
                />
              </MergeMethodContextProvider>
            </FeatureFlagProvider>
          </PageDataContextProvider>
        </AppPayloadContext.Provider>
      </RoutesContext.Provider>
    </AliveTestProvider>
  )
}
