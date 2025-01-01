import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'

import {useRoutePayload} from '@github-ui/react-core/use-route-payload'

import type {IndexModelsPayload} from '../../types'

import {Label, Link, PageLayout} from '@primer/react'
import MarketplaceHeader from '@github-ui/marketplace-common/MarketplaceHeader'
import MarketplaceNavigation from '@github-ui/marketplace-common/MarketplaceNavigation'
import ModelItem from './components/ModelItem'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import ModelsIndexFilters from '../../components/ModelsIndexFilters'
import {isFeatureEnabled} from '@github-ui/feature-flags'

export const docsUrl = 'https://docs.github.com/github-models/prototyping-with-ai-models'
export const feedbackUrl = 'https://gh.io/models-feedback'

export function ModelsIndexRoute() {
  const payload = useRoutePayload<IndexModelsPayload>()
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')

  return (
    <>
      <MarketplaceHeader />
      <PageLayout>
        <PageLayout.Pane position="start">
          <MarketplaceNavigation categories={payload.categories} />
        </PageLayout.Pane>
        <PageLayout.Content as="div">
          <div className="d-flex flex-column flex-sm-row flex-justify-between flex-wrap gap-2 mb-4">
            <div>
              <h2 className="f2 lh-condensed">Models</h2>
              <p className="fgColor-muted mb-0">
                Try, test, and deploy from a wide range of model types, sizes, and specializations.{' '}
                <Link inline href={docsUrl}>
                  Learn more
                </Link>
                .
              </p>
            </div>
            {lifecycleLabelNameEnabled ? (
              <BetaLabel feedbackUrl={feedbackUrl} />
            ) : (
              <div className="d-flex flex-items-center gap-2">
                <Label variant="success">Beta</Label>
                <Link href={feedbackUrl}>Give feedback</Link>
              </div>
            )}
          </div>

          <ModelsIndexFilters />

          <div className={`mt-4 ${commonStyles['marketplace-list-grid']}`}>
            {payload.models?.map(model => <ModelItem key={model.name} model={model} />)}
          </div>
        </PageLayout.Content>
      </PageLayout>
    </>
  )
}
