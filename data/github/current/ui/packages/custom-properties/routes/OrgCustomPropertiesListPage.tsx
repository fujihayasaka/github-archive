import {debounce} from '@github/mini-throttle'
import {announce} from '@github-ui/aria-live'
import type {OrgCustomPropertiesListPagePayload} from '@github-ui/custom-properties-types'
import {Filter} from '@github-ui/filter'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Pagination} from '@primer/react'
import {useEffect, useState} from 'react'

import {DefinitionsList} from '../components/DefinitionsList'
import {PropertiesHeaderPageTabs} from '../components/PropertiesHeaderPageTabs'
import {usePropertiesListResults} from '../hooks/use-properties-list'

const debounceAnnounce = debounce(announce, 300)

export function OrgCustomPropertiesListPage() {
  const {permissions, business, ownDefinitionsCount, ...payload} = useRoutePayload<OrgCustomPropertiesListPagePayload>()
  const propertiesListExperienceEnabled = useFeatureFlag('enterprise_custom_properties_list')

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
      <PropertiesHeaderPageTabs
        activeTab="properties"
        permissions={permissions}
        ownDefinitionsCount={ownDefinitionsCount}
        totalDefinitionsCount={totalCount}
      />
      {propertiesListExperienceEnabled && (
        <Filter
          id="properties-filter"
          className="mb-3"
          variant="input"
          providers={[]}
          label="Filter properties"
          filterValue={filterQuery}
          onChange={setFilterQuery}
          onSubmit={r => fetchResults({page: 1, filterQuery: r.raw})}
        />
      )}
      <DefinitionsList totalCount={totalCount} definitions={definitions} business={business} />

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
