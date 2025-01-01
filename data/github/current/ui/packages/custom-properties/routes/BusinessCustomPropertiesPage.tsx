import {debounce} from '@github/mini-throttle'
import {announce} from '@github-ui/aria-live'
import type {BusinessCustomPropertiesDefinitionsPagePayload} from '@github-ui/custom-properties-types'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Pagination} from '@primer/react'
import {useEffect, useState} from 'react'

import {DefinitionsList} from '../components/DefinitionsList'
import {DefinitionsPageHeader} from '../components/PropertiesHeaderPageTabs'
import {usePropertiesListResults} from '../hooks/use-properties-list'
import {usePropertySource} from '../hooks/use-property-source'
import {DefinitionsFilter} from './DefinitionsFilter'

const debounceAnnounce = debounce(announce, 300)

export function BusinessCustomPropertiesPage() {
  const {ownDefinitionsCount, ...payload} = useRoutePayload<BusinessCustomPropertiesDefinitionsPagePayload>()
  const propertiesListExperienceEnabled = useFeatureFlag('enterprise_custom_properties_list')
  const {sourceName} = usePropertySource()

  const [filterQuery, setFilterQuery] = useState('')

  const {
    payload: {totalCount, pageCount, definitions},
    currentPage,
    fetchResults,
  } = usePropertiesListResults({initialPayload: payload})

  useEffect(() => {
    debounceAnnounce(`${totalCount} ${totalCount === 1 ? 'property' : 'properties'} found.`)
  }, [definitions, totalCount])

  return (
    <>
      <DefinitionsPageHeader permissions="definitions" ownDefinitionsCount={ownDefinitionsCount} betaLabel />
      {propertiesListExperienceEnabled && (
        <DefinitionsFilter
          className="mb-3"
          filterValue={filterQuery}
          onChange={setFilterQuery}
          businessSlug={sourceName}
          onSubmit={query => fetchResults({page: 1, filterQuery: query})}
        />
      )}

      <DefinitionsList totalCount={totalCount} definitions={definitions} />
      {propertiesListExperienceEnabled && pageCount > 1 && (
        <Pagination
          currentPage={currentPage}
          pageCount={pageCount}
          onPageChange={(e, page) => {
            e.preventDefault() // Prevent click event from navigating
            fetchResults({page, filterQuery})
          }}
        />
      )}
    </>
  )
}
