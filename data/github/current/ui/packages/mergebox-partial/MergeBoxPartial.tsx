import {MergeMethodContextProvider, validateMergeMethod, MergeBoxWithSuspense} from '@github-ui/mergebox'
import {MergeMethod} from '@github-ui/mergebox/types'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'

export interface MergeBoxPartialProps {
  defaultMergeMethod: MergeMethod
  pullRequestId: string
  basePageDataUrl: string
  viewerLogin: string
  helpUrl: string
}

export function MergeBoxPartial({
  defaultMergeMethod,
  pullRequestId,
  basePageDataUrl,
  viewerLogin,
  helpUrl,
}: MergeBoxPartialProps) {
  const mergeMethod = validateMergeMethod(defaultMergeMethod) ? defaultMergeMethod : MergeMethod.MERGE
  const analyticsMetadata = {pullRequestId, view: 'show'}

  return (
    <PageDataContextProvider basePageDataUrl={basePageDataUrl}>
      <AnalyticsProvider appName="pull_request" category="mergebox_react_partial" metadata={analyticsMetadata}>
        <MergeMethodContextProvider defaultMergeMethod={mergeMethod}>
          <div className="ml-md-6 pl-md-3 my-3" data-testid="mergebox-partial">
            <MergeBoxWithSuspense helpUrl={helpUrl} viewerLogin={viewerLogin} />
          </div>
        </MergeMethodContextProvider>
      </AnalyticsProvider>
    </PageDataContextProvider>
  )
}
