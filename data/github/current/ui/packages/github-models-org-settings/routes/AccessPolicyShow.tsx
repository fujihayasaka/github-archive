import {Heading} from '@primer/react'
import {ModelsGlobalAccessToggle} from '../components/ModelsGlobalAccessToggle'
import {ModelsPermissions} from '../components/ModelsPermissions'
import {OrganizationAccessPolicyProvider} from '../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../contexts/PublishersContext'
import {TermsAndPrivacyNotice} from '../components/TermsAndPrivacyNotice'
import {ModelsPermissionsHeader} from '../components/ModelsPermissionsHeader'
import {ModelsBilling} from '../components/ModelsBilling'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {accessPolicyShow} from './access-policy-show-route'

export function AccessPolicyShow() {
  const {
    data: {models, publishers, billingEnabled, policy, orgDisplayLogin, canEnableModelsBilling},
  } = useRouteQuery(accessPolicyShow, 'mainQuery')

  return (
    <OrganizationAccessPolicyProvider orgDisplayLogin={orgDisplayLogin} policy={policy}>
      <PublishersProvider models={models} publishers={publishers}>
        <div className="Subhead">
          <Heading as="h2" data-hpc variant="medium" className="Subhead-heading Subhead-heading--large">
            Models
          </Heading>
        </div>
        <ModelsGlobalAccessToggle />
        <TermsAndPrivacyNotice />
        <ModelsBilling
          billingEnabled={billingEnabled}
          orgDisplayLogin={orgDisplayLogin}
          canEnableModelsBilling={canEnableModelsBilling}
        />
        <ModelsPermissionsHeader />
        <ModelsPermissions models={models} publishers={publishers} />
      </PublishersProvider>
    </OrganizationAccessPolicyProvider>
  )
}
