import type {OrgEditPermissions, PropertiesPageTabName} from '@github-ui/custom-properties-types'
import {Link} from '@github-ui/react-core/link'
import {Box, Button} from '@primer/react'

import {useNewPropertyPath} from '../hooks/use-property-details-paths'
import {DefinitionsLimitBanner, isDefinitionsLimitReached} from './Banners'
import {PropertyPageHeader} from './PageHeader'
import {PropertiesPageTabs} from './PropertiesPageTabs'

export function PropertiesHeaderPageTabs({
  activeTab,
  permissions,
  ownDefinitionsCount,
  totalDefinitionsCount,
}: {
  permissions: OrgEditPermissions
  activeTab: PropertiesPageTabName
  ownDefinitionsCount: number
  totalDefinitionsCount: number
}) {
  return (
    <>
      <DefinitionsPageHeader ownDefinitionsCount={ownDefinitionsCount} permissions={permissions} />
      {permissions === 'all' && <PropertiesPageTabs activeTab={activeTab} definitionsCount={totalDefinitionsCount} />}
    </>
  )
}

export function DefinitionsPageHeader({
  ownDefinitionsCount,
  permissions,
  betaLabel,
}: {
  ownDefinitionsCount: number
  permissions: OrgEditPermissions
  betaLabel?: boolean
}) {
  const newPropertyPath = useNewPropertyPath()

  // Currently, only at the org level, there can be a mix of org props and business props
  const definitionLimitReached = isDefinitionsLimitReached(ownDefinitionsCount)

  const canCreateProperty = !definitionLimitReached && (permissions === 'all' || permissions === 'definitions')

  return (
    <>
      <PropertyPageHeader
        title="Custom properties"
        subtitle="Custom properties allow you to decorate your repositories with information such as compliance frameworks, data
      sensitivity, or project details."
        actions={
          canCreateProperty && (
            <Button as={Link} to={newPropertyPath} variant="primary" data-testid="add-definition-button">
              New property
            </Button>
          )
        }
        betaLabel={betaLabel}
      />
      {definitionLimitReached && (
        <Box sx={{mb: 2}}>
          <DefinitionsLimitBanner />
        </Box>
      )}
    </>
  )
}
