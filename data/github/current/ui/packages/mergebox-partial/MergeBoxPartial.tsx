import {MergeMethodContextProvider, validateMergeMethod, MergeBoxWithSuspense} from '@github-ui/mergebox'
import {MergeMethod} from '@github-ui/mergebox/types'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {FeatureFlagProvider} from '@github-ui/react-core/feature-flag-provider'
import type {EnabledFeatures} from '@github-ui/react-core/use-feature-flag'
import type {Channels} from '@github-ui/mergebox/use-mergeability-live-updates'

export interface MergeBoxPartialProps {
  defaultMergeMethod: MergeMethod
  pullRequestId: string
  basePageDataUrl: string
  viewerLogin: string
  helpUrl: string
  enabledFeatures: EnabledFeatures
  channels: Channels
}

export function MergeBoxPartial({
  channels,
  defaultMergeMethod,
  pullRequestId,
  basePageDataUrl,
  viewerLogin,
  helpUrl,
  enabledFeatures,
}: MergeBoxPartialProps) {
  const mergeMethod = validateMergeMethod(defaultMergeMethod) ? defaultMergeMethod : MergeMethod.MERGE
  const analyticsMetadata = {pullRequestId, view: 'show'}

  return (
    <PageDataContextProvider basePageDataUrl={basePageDataUrl}>
      <FeatureFlagProvider features={enabledFeatures ?? {}}>
        <AnalyticsProvider appName="pull_request" category="mergebox_react_partial" metadata={analyticsMetadata}>
          <MergeMethodContextProvider defaultMergeMethod={mergeMethod}>
            <div className="ml-md-6 pl-md-3 my-3" data-testid="mergebox-partial">
              <MergeBoxWithSuspense helpUrl={helpUrl} viewerLogin={viewerLogin} channels={channels} />
            </div>
          </MergeMethodContextProvider>
        </AnalyticsProvider>
      </FeatureFlagProvider>
    </PageDataContextProvider>
  )
}
