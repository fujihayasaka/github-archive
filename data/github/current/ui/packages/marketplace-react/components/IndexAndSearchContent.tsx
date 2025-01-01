import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'
import styles from './IndexAndSearchContent.module.css'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Heading, UnderlineNav} from '@primer/react'
import MarketplaceItem from '../components/MarketplaceItem'
import type {IndexPayload} from '@github-ui/marketplace-common'
import {useState} from 'react'
import ResultList from '../components/ResultList'
import {useFilterContext} from '@github-ui/marketplace-common/FilterContext'
import {useFeaturedListings} from '@github-ui/marketplace-common/FeaturedListingsContext'
import {useRecommendedListings} from '@github-ui/marketplace-common/RecommendedListingsContext'
import {useRecentlyAddedListings} from '@github-ui/marketplace-common/RecentlyAddedListingsContext'
import ModelItem from '@github-ui/github-models/ModelItem'

type Props = {
  payload: IndexPayload
}
export function IndexAndSearchContent({payload}: Props) {
  const {featuredModels} = useRoutePayload<IndexPayload>()
  const {isSearching} = useFilterContext()
  const {recentlyAdded} = useRecentlyAddedListings()
  const {featured} = useFeaturedListings()
  const {recommended} = useRecommendedListings()
  const [currentList, setCurrentList] = useState<'recommended' | 'recentlyAdded'>('recommended')

  return (
    <>
      {isSearching ? (
        <ResultList categories={payload.categories} />
      ) : (
        <>
          <Heading as="h2" className="f2">
            Models for your every use case
          </Heading>
          <span className="fgColor-muted">
            Try, test, and deploy from a wide range of model types, sizes, and specializations.
          </span>
          <div className={`mt-4 ${commonStyles['marketplace-featured-grid']} width-fit`}>
            {featuredModels.map(model => (
              <ModelItem key={model.id} model={model} isFeatured />
            ))}
          </div>
          <Heading as="h2" className="mt-4 f2">
            Discover apps with Copilot extensions
          </Heading>
          <span className="fgColor-muted">Your favorite tools now work with GitHub Copilot.</span>
          <div className={`mt-4 ${commonStyles['marketplace-featured-grid']} width-fit`}>
            {featured.map(listing => (
              <MarketplaceItem key={`${listing.type}-${listing.id}`} listing={listing} isFeatured />
            ))}
          </div>
          <div className={styles.UnderlineNavContainer}>
            <UnderlineNav aria-label="View recommended or recent marketplace listings">
              <UnderlineNav.Item
                as="button"
                aria-current={currentList === 'recommended' ? 'page' : undefined}
                onSelect={event => {
                  event?.preventDefault()
                  setCurrentList('recommended')
                }}
              >
                Recommended
              </UnderlineNav.Item>
              <UnderlineNav.Item
                as="button"
                aria-current={currentList === 'recentlyAdded' ? 'page' : undefined}
                onSelect={event => {
                  event?.preventDefault()
                  setCurrentList('recentlyAdded')
                }}
              >
                Recently added
              </UnderlineNav.Item>
            </UnderlineNav>
          </div>
          {currentList === 'recommended' && (
            <div className={`mt-4 ${commonStyles['marketplace-list-grid']}`}>
              {recommended.map(listing => (
                <MarketplaceItem key={`${listing.type}-${listing.id}`} listing={listing} isFeatured={false} />
              ))}
            </div>
          )}
          {currentList === 'recentlyAdded' && (
            <div className={`mt-4 ${commonStyles['marketplace-list-grid']}`}>
              {recentlyAdded.map(listing => (
                <MarketplaceItem key={`${listing.type}-${listing.id}`} listing={listing} isFeatured={false} />
              ))}
            </div>
          )}
        </>
      )}
    </>
  )
}
