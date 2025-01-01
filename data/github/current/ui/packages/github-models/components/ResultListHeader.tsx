import {useMemo, useState} from 'react'
import {Label, Link, LinkButton, UnderlineNav} from '@primer/react'
import {BetaLabel} from '@github-ui/lifecycle-labels/beta'
import {CommandPaletteIcon} from '@primer/octicons-react'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {testIdProps} from '@github-ui/test-id-props'
import {useQuery} from '@github-ui/marketplace-common/QueryContext'
import {useSearchResults} from '@github-ui/marketplace-common/SearchResultsContext'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {IndexPayload} from '@github-ui/marketplace-common'
import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'
import ModelItem from './ModelItem'
import {modelsPlaygroundPath} from '@github-ui/paths'

import styles from './ResultListHeader.module.css'

export const modelsFeedbackUrl = 'https://gh.io/models-feedback'

type FeaturedModelsType = 'recent' | 'popular'

export function ResultListHeader() {
  const [featuredModelsType, setFeaturedModelsType] = useState<FeaturedModelsType>('recent')
  const lifecycleLabelNameEnabled = isFeatureEnabled('lifecycle_label_name_updates')
  const {query} = useQuery()
  const {searchResults} = useSearchResults()
  const {recentModels, popularModels} = useRoutePayload<IndexPayload>()

  const models = useMemo(
    () => (featuredModelsType === 'popular' ? popularModels : recentModels),
    [featuredModelsType, popularModels, recentModels],
  )

  return (
    <>
      <div className="mb-4 d-flex flex-column flex-sm-row flex-justify-between flex-wrap gap-2">
        <div>
          <h2 className="f2 lh-condensed" {...testIdProps('heading-text')}>
            {query ? `Search results for “${query}”` : 'Models'}
          </h2>
          <span className="fgColor-muted" {...testIdProps('detail-text')}>
            {query ? (
              `${searchResults.total} ${searchResults.total === 1 ? 'result' : 'results'}`
            ) : (
              <span>
                Create applications with GitHub powered by AI Models. Free to use, quick personal setup, and seamless
                model switching to help you build AI products using the latest models.
              </span>
            )}
          </span>
        </div>

        {lifecycleLabelNameEnabled ? (
          <BetaLabel feedbackUrl={modelsFeedbackUrl} />
        ) : (
          <div className="d-flex flex-items-center gap-2">
            <Label variant="success">Beta</Label>
            <Link href={modelsFeedbackUrl} tabIndex={0}>
              Give feedback
            </Link>
          </div>
        )}
      </div>
      <div className={`mb-4 d-flex flex-items-center justify-center ${styles.nav}`}>
        <div className="flex-1">
          {/* eslint-disable-next-line @github-ui/github-monorepo/no-sx */}
          <UnderlineNav aria-label="Featured models sort order" sx={{boxShadow: 'none', paddingInline: '0'}}>
            <UnderlineNav.Item
              as="button"
              href=""
              aria-current={featuredModelsType === 'recent' ? 'page' : undefined}
              onSelect={() => setFeaturedModelsType('recent')}
            >
              Recently added
            </UnderlineNav.Item>
            <UnderlineNav.Item
              as="button"
              href=""
              aria-current={featuredModelsType === 'popular' ? 'page' : undefined}
              onSelect={() => setFeaturedModelsType('popular')}
            >
              Most popular
            </UnderlineNav.Item>
          </UnderlineNav>
        </div>
        <LinkButton href={modelsPlaygroundPath()} variant="primary" leadingVisual={<CommandPaletteIcon />} tabIndex={0}>
          Try models in playground
        </LinkButton>
      </div>
      <div className={`mb-4 ${commonStyles['marketplace-featured-grid']} width-fit`}>
        {models.map(model => (
          <ModelItem key={model.id} model={model} isFeatured />
        ))}
      </div>
    </>
  )
}
