import type {PropsWithChildren} from 'react'
import {FilterProvider} from './FilterContext'
import {SearchResultsProvider} from './SearchResultsContext'
import {SortProvider} from './SortContext'
import {FeaturedListingsProvider} from './FeaturedListingsContext'
import {RecommendedListingsProvider} from './RecommendedListingsContext'
import {RecentlyAddedListingsProvider} from './RecentlyAddedListingsContext'
import {CreatorsProvider} from './CreatorsContext'
import {CategoryProvider} from './CategoryContext'
import {SearchTypeProvider} from './SearchTypeContext'
import {CopilotAppProvider} from './CopilotAppContext'
import {ModelsTaskProvider} from './ModelsTaskContext'
import {ModelsPublisherProvider} from './ModelsPublisherContext'

export function SearchAndFilterProviderStack({children}: PropsWithChildren) {
  return (
    <SearchResultsProvider>
      <SortProvider>
        <FeaturedListingsProvider>
          <RecommendedListingsProvider>
            <RecentlyAddedListingsProvider>
              <CreatorsProvider>
                <CategoryProvider>
                  <SearchTypeProvider>
                    <CopilotAppProvider>
                      <ModelsTaskProvider>
                        <ModelsPublisherProvider>
                          <FilterProvider>{children}</FilterProvider>
                        </ModelsPublisherProvider>
                      </ModelsTaskProvider>
                    </CopilotAppProvider>
                  </SearchTypeProvider>
                </CategoryProvider>
              </CreatorsProvider>
            </RecentlyAddedListingsProvider>
          </RecommendedListingsProvider>
        </FeaturedListingsProvider>
      </SortProvider>
    </SearchResultsProvider>
  )
}
