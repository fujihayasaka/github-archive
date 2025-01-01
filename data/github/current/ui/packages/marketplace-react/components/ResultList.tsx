import styles from '../marketplace.module.css'
import commonStyles from '@github-ui/marketplace-common/marketplace-common.module.css'

import {Pagination} from '@primer/react'
import {SearchIcon} from '@primer/octicons-react'
import {Blankslate} from '@primer/react/experimental'
import {useCallback} from 'react'
import Filters from './Filters'
import MarketplaceItem from './MarketplaceItem'
import type {Category} from '@github-ui/marketplace-common'
import {useSearchResults} from '@github-ui/marketplace-common/SearchResultsContext'
import {usePage} from '@github-ui/marketplace-common/PageContext'
import {ResultListHeader} from './ResultListHeader'

type Props = {
  categories: {
    apps: Category[]
    actions: Category[]
  }
}

export default function ResultList({categories}: Props) {
  const {searchResults} = useSearchResults()
  const {page, setPage} = usePage()

  const onPageChange = useCallback(
    (e: React.MouseEvent, p: number) => {
      e.preventDefault()
      setPage(p)
    },
    [setPage],
  )

  return (
    <>
      <ResultListHeader categories={categories} />

      <div className="mt-3">
        <Filters />
      </div>

      {searchResults.results.length > 0 ? (
        <>
          <div
            className={`mt-4 ${
              searchResults.results.length === 1
                ? styles['marketplace-list-grid-one']
                : commonStyles['marketplace-list-grid']
            }`}
            data-testid="search-results"
          >
            {searchResults.results.map(listing => (
              <MarketplaceItem key={`${listing.type}-${listing.id}`} listing={listing} isFeatured={false} />
            ))}
          </div>
          {(searchResults.totalPages ?? 1) > 1 && (
            <Pagination
              pageCount={searchResults.totalPages ?? 1}
              currentPage={page}
              onPageChange={onPageChange}
              showPages={{
                narrow: false,
              }}
            />
          )}
        </>
      ) : (
        <div className="mt-4">
          <Blankslate border>
            <Blankslate.Visual>
              <SearchIcon size="medium" />
            </Blankslate.Visual>
            <Blankslate.Heading>No results</Blankslate.Heading>
            <Blankslate.Description>Try searching by different keywords.</Blankslate.Description>
          </Blankslate>
        </div>
      )}
    </>
  )
}
