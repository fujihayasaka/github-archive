import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {Box, Heading} from '@primer/react'
import {useEffect, useState} from 'react'
import {useQueryLoader} from 'react-relay'

import {ResourceType} from '../../enums/cost-centers'
import {Fonts, Spacing} from '../../utils/style'

import {ErrorBanner} from '../common/ErrorBanner'
import {OrganizationPicker, OrganizationPickerRecentQuery} from '../pickers/OrganizationPicker'
import type {OrganizationPickerRecentQuery as OrganizationPickerQueryType} from '../pickers/__generated__/OrganizationPickerRecentQuery.graphql'
import {RepositoryPicker, RepositoryPickerRecentQuery} from '../pickers/RepositoryPicker'
import type {RepositoryPickerRecentQuery as RepositoryPickerQueryType} from '../pickers/__generated__/RepositoryPickerRecentQuery.graphql'

import type {Customer} from '../../types/common'
import type {CostCenterPicker, Resource} from '../../types/cost-centers'
import {PickerLoadingSkeleton} from '../pickers/PickerLoadingSkeleton'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {OrganizationPickerParentGraphqlQuery, PaginatedOrganizationPicker} from '../pickers/PaginatedOrganizationPicker'
import type {PaginatedOrganizationPickerGraphqlQuery} from '../pickers/__generated__/PaginatedOrganizationPickerGraphqlQuery.graphql'
import type {PaginatedRepositoryPickerGraphqlQuery} from '../pickers/__generated__/PaginatedRepositoryPickerGraphqlQuery.graphql'
import {
  PaginatedRepositoryPicker,
  PaginatedRepositoryPickerParentGraphqlQuery,
} from '../pickers/PaginatedRepositoryPicker'

interface Props {
  customer: Customer
  resources: Resource[]
  setCostCenterResources: (resources: Resource[]) => void
  // Optionally disable the org or repo picker or both
  disablePicker?: CostCenterPicker[]
  // Optionally display the resource selector in view-only mode
  viewOnly?: boolean
}

function useFetchOrganizations(customer: Customer, disablePicker?: CostCenterPicker[]) {
  const [organizationsRef, loadOrganizations, disposeOrganizationsRef] =
    useQueryLoader<OrganizationPickerQueryType>(OrganizationPickerRecentQuery)

  useEffect(() => {
    if (!disablePicker?.includes('org')) {
      loadOrganizations({slug: customer.displayId, query: null}, {fetchPolicy: 'store-or-network'})
    }

    return () => disposeOrganizationsRef()
  }, [loadOrganizations, disposeOrganizationsRef, disablePicker, customer.displayId])

  return organizationsRef
}

function useFetchPaginatedOrganizations(customer: Customer, disablePicker?: CostCenterPicker[]) {
  const [paginatedOrganizationsRef, loadPaginatedOrganizations, disposePaginatedOrganizationsRef] =
    useQueryLoader<PaginatedOrganizationPickerGraphqlQuery>(OrganizationPickerParentGraphqlQuery)

  useEffect(() => {
    if (!disablePicker?.includes('org')) {
      loadPaginatedOrganizations({slug: customer.displayId, query: null}, {fetchPolicy: 'store-or-network'})
    }

    return () => disposePaginatedOrganizationsRef()
  }, [loadPaginatedOrganizations, disposePaginatedOrganizationsRef, disablePicker, customer.displayId])

  return paginatedOrganizationsRef
}

function useFetchRepositories(customer: Customer, disablePicker?: CostCenterPicker[]) {
  const [repositoriesRef, loadRepositories, disposeRepositoriesRef] =
    useQueryLoader<RepositoryPickerQueryType>(RepositoryPickerRecentQuery)
  useEffect(() => {
    if (!disablePicker?.includes('repo')) {
      loadRepositories({slug: customer.displayId}, {fetchPolicy: 'store-or-network'})
    }
    return () => {
      disposeRepositoriesRef()
    }
  }, [loadRepositories, disposeRepositoriesRef, disablePicker, customer.displayId])
  return repositoriesRef
}

function useFetchPaginatedRepositories(customer: Customer, disablePicker?: CostCenterPicker[]) {
  const [paginatedRepositoriesRef, loadPaginatedRepositories, disposePaginatedRepositoriesRef] =
    useQueryLoader<PaginatedRepositoryPickerGraphqlQuery>(PaginatedRepositoryPickerParentGraphqlQuery)
  useEffect(() => {
    if (!disablePicker?.includes('repo')) {
      loadPaginatedRepositories({slug: customer.displayId}, {fetchPolicy: 'store-or-network'})
    }
    return () => {
      disposePaginatedRepositoriesRef()
    }
  }, [loadPaginatedRepositories, disposePaginatedRepositoriesRef, disablePicker, customer.displayId])
  return paginatedRepositoriesRef
}

export function CostCenterResourceSelector({
  customer,
  resources,
  setCostCenterResources,
  disablePicker,
  viewOnly = false,
}: Props) {
  const [loadOrgsError, setLoadOrgsError] = useState<Error>()
  const [loadReposError, setLoadReposError] = useState<Error>()
  const usePaginatedOrgPickerCostCenterForm = isFeatureEnabled('use_paginated_org_picker_cost_center_form')
  const usePaginatedRepoPickerCostCenterForm = isFeatureEnabled('use_paginated_repo_picker_cost_center_form')

  const organizationsRef = useFetchOrganizations(customer, disablePicker)

  const repositoriesRef = useFetchRepositories(customer, disablePicker)

  const paginatedOrganizationsRef = useFetchPaginatedOrganizations(customer, disablePicker)

  const paginatedRepositoriesRef = useFetchPaginatedRepositories(customer, disablePicker)

  function handleOrgsGQLError(e: Error) {
    setLoadOrgsError(e)
  }

  function handleReposGQLError(e: Error) {
    setLoadReposError(e)
  }

  const resourceByOrg = resources.filter(resource => resource.type === ResourceType.Org).map(resource => resource.id)
  const resourceByRepo = resources.filter(resource => resource.type === ResourceType.Repo).map(resource => resource.id)

  const filterByType = (selectedIds: string[], type: ResourceType) => {
    const tmp = resources.filter(item => item.type !== type)
    const newResources = selectedIds.map(item => {
      const resource: Resource = {type, id: String(item)}
      return resource
    })
    setCostCenterResources(tmp.concat(newResources))
  }

  const setOrgIds = (orgs: string[]) => {
    filterByType(orgs, ResourceType.Org)
  }

  const setRepoIds = (repos: string[]) => {
    filterByType(repos, ResourceType.Repo)
  }

  const resourcePickerStyle = {
    mb: Spacing.CardMargin,
    p: 3,
  }

  return (
    <Box sx={{mb: Spacing.CardMargin}}>
      <Box sx={{mb: 2}}>
        <Heading as="h3" className="h2-override-shared-component" sx={{fontSize: Fonts.SectionHeadingFontSize}}>
          Resources
        </Heading>
        {!viewOnly && (
          <span>
            Set the resources that will be a part of this cost center. A maximum of 50 resources can be added or removed
            at a time.
          </span>
        )}
      </Box>

      {!disablePicker?.includes('org') && (
        <Box className="Box" data-testid="org-picker-wrapper" sx={resourcePickerStyle}>
          <ErrorBoundary onError={handleOrgsGQLError}>
            {usePaginatedOrgPickerCostCenterForm ? (
              paginatedOrganizationsRef ? (
                <PaginatedOrganizationPicker
                  preloadedOrganizationsRef={paginatedOrganizationsRef}
                  setSelectedItems={setOrgIds}
                  initialSelectedItemIds={resourceByOrg}
                  selectionVariant="multiple"
                  indent={false}
                  entityType="cost center"
                  viewOnly={viewOnly}
                />
              ) : (
                <PickerLoadingSkeleton title="Organizations" totalCount={resourceByOrg.length} viewOnly={viewOnly} />
              )
            ) : organizationsRef ? (
              <OrganizationPicker
                slug={customer.displayId}
                preloadedOrganizationsRef={organizationsRef}
                setSelectedItems={setOrgIds}
                initialSelectedItemIds={resourceByOrg}
                selectionVariant="multiple"
                indent={false}
                entityType="cost center"
                viewOnly={viewOnly}
              />
            ) : (
              <PickerLoadingSkeleton title="Organizations" totalCount={resourceByOrg.length} viewOnly={viewOnly} />
            )}
          </ErrorBoundary>
          {loadOrgsError && <ErrorBanner message={loadOrgsError.cause as string} sx={{mt: 2, mb: 0}} />}
        </Box>
      )}
      {!disablePicker?.includes('repo') && (
        <Box className="Box" data-testid="repo-picker-wrapper" sx={resourcePickerStyle}>
          <ErrorBoundary onError={handleReposGQLError}>
            {usePaginatedRepoPickerCostCenterForm ? (
              paginatedRepositoriesRef ? (
                <PaginatedRepositoryPicker
                  slug={customer.displayId}
                  preloadedRepositoriesRef={paginatedRepositoriesRef}
                  setSelectedItems={setRepoIds}
                  initialSelectedItemIds={resourceByRepo}
                  selectionVariant="multiple"
                  indent={false}
                  entityType="cost center"
                  viewOnly={viewOnly}
                />
              ) : (
                <PickerLoadingSkeleton title="Repositories" totalCount={resourceByRepo.length} viewOnly={viewOnly} />
              )
            ) : repositoriesRef ? (
              <RepositoryPicker
                slug={customer.displayId}
                preloadedRepositoriesRef={repositoriesRef}
                setSelectedItems={setRepoIds}
                initialSelectedItemIds={resourceByRepo}
                selectionVariant="multiple"
                indent={false}
                entityType="cost center"
                viewOnly={viewOnly}
              />
            ) : (
              <PickerLoadingSkeleton title="Repositories" totalCount={resourceByRepo.length} viewOnly={viewOnly} />
            )}
          </ErrorBoundary>
          {loadReposError && <ErrorBanner message={loadReposError.cause as string} sx={{mt: 2, mb: 0}} />}
        </Box>
      )}
    </Box>
  )
}
