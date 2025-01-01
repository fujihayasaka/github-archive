import {debounce} from '@github/mini-throttle'
import {announce} from '@github-ui/aria-live'
import type {OrgCustomPropertiesListPagePayload} from '@github-ui/custom-properties-types'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {Pagination} from '@primer/react'
import {useEffect, useState} from 'react'

import {DefinitionsList} from '../components/DefinitionsList'
import {PropertiesHeaderPageTabs} from '../components/PropertiesHeaderPageTabs'
import {usePropertiesListResults} from '../hooks/use-properties-list'
import {DefinitionsFilter} from './DefinitionsFilter'

const debounceAnnounce = debounce(announce, 300)

export function OrgCustomPropertiesListPage() {
  const {permissions, ownDefinitionsCount, ...payload} = useRoutePayload<OrgCustomPropertiesListPagePayload>()
  const showFilterDialog = useFeatureFlag('repos_list_show_filter_dialog')

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
      <DefinitionsFilter
        className="mb-3"
        variant={showFilterDialog ? 'full' : 'input'}
        filterValue={filterQuery}
        onChange={setFilterQuery}
        onSubmit={request => fetchResults({page: 1, filterQuery: request.raw})}
      />
      <DefinitionsList totalCount={totalCount} definitions={definitions} />

      {pageCount > 1 && (
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
