import {Heading} from '@primer/react'
import {ModelsGlobalAccessToggle} from '../components/ModelsGlobalAccessToggle'
import {ModelsPermissions} from '../components/ModelsPermissions'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {TermsAndPrivacyNotice} from '../components/TermsAndPrivacyNotice'
import {ModelsPermissionsHeader} from '../components/ModelsPermissionsHeader'

export function AccessPolicyShow() {
  return (
    <OrganizationAccessPolicyProvider>
      <PublishersProvider>
        <div className="Subhead">
          <Heading as="h2" data-hpc variant="medium" className="Subhead-heading Subhead-heading--large">
            Models
          </Heading>
        </div>
        <ModelsGlobalAccessToggle />
        <TermsAndPrivacyNotice />
        <ModelsPermissionsHeader />
        <ModelsPermissions />
      </PublishersProvider>
    </OrganizationAccessPolicyProvider>
  )
}
