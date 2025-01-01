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
  const showFilterDialog = useFeatureFlag('repos_list_show_filter_dialog')
  const {sourceName} = usePropertySource()

  const {
    payload: {totalCount, pageCount, definitions, currentQ},
    currentPage,
    fetchResults,
  } = usePropertiesListResults({initialPayload: payload})

  const [filterQuery, setFilterQuery] = useState(currentQ)

  useEffect(() => {
    debounceAnnounce(`${totalCount} ${totalCount === 1 ? 'property' : 'properties'} found.`)
  }, [definitions, totalCount])

  return (
    <>
      <DefinitionsPageHeader permissions="definitions" ownDefinitionsCount={ownDefinitionsCount} betaLabel />
      {propertiesListExperienceEnabled && (
        <DefinitionsFilter
          className="mb-3"
          variant={showFilterDialog ? 'full' : 'input'}
          filterValue={filterQuery}
          onChange={setFilterQuery}
          businessSlug={sourceName}
          onSubmit={request => fetchResults({page: 1, filterQuery: request.raw})}
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
