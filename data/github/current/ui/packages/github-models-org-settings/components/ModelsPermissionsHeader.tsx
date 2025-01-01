import {Heading} from '@primer/react'
import {useOrganizationAccessPolicy} from '../contexts/OrganizationAccessPolicyContext'

export function ModelsPermissionsHeader() {
  const {isModelsEnabled} = useOrganizationAccessPolicy()

  if (!isModelsEnabled) return null

  return (
    <div className="Subhead mt-4">
      <Heading as="h2" data-hpc variant="medium" className="Subhead-heading Subhead-heading--large">
        Models permissions
      </Heading>
    </div>
  )
}
