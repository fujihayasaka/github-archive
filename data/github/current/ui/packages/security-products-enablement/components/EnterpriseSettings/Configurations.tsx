import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {
  settingsBusinessSecurityAnalysisConfigurationsNewPath,
  settingsBusinessSecurityAnalysisPoliciesPath,
} from '@github-ui/paths'
import {useAppContext} from '../../contexts/AppContext'
import SecurityConfigurationRow from '../SecurityConfiguration/Row'
import type {EnterpriseSettingsPayload} from '../../security-products-enablement-types'
import NewConfigurationButton from '../SecurityConfiguration/NewConfigurationButton'
import OrgFailuresBanner from './OrgFailuresBanner'
import {Link as PrimerLink} from '@primer/react'

const Configurations: React.FC = () => {
  const {enterprise, githubRecommendedConfiguration, customEnterpriseSecurityConfigurations} = useAppContext()
  const {orgFailures} = useRoutePayload<EnterpriseSettingsPayload>()

  return (
    <>
      <div data-testid="enterprise-configurations" className="mb-5">
        <OrgFailuresBanner failures={orgFailures} />

        <div>
          <div className="d-flex flex-items-start">
            <div className="flex-1">
              <h2
                className="Subhead-heading h2-override-shared-component"
                style={{display: 'inline-flex', alignItems: 'center'}}
              >
                Configurations
              </h2>
              <div data-testid="subhead-description" className="Subhead-description mt-1 mb-3">
                Define and apply security configurations to make sure your repositories are protected. Manage Advanced
                Security access for your organizations{' '}
                <PrimerLink
                  inline
                  href={settingsBusinessSecurityAnalysisPoliciesPath({business: enterprise?.slug || ''})}
                >
                  under Policies
                </PrimerLink>
                .
              </div>
            </div>
            <div className="mt-1 ml-3">
              <NewConfigurationButton
                link={settingsBusinessSecurityAnalysisConfigurationsNewPath({business: enterprise?.slug || ''})}
              />
            </div>
          </div>
        </div>

        <div>
          {githubRecommendedConfiguration && (
            <SecurityConfigurationRow
              configuration={githubRecommendedConfiguration}
              isFirst
              isLast={customEnterpriseSecurityConfigurations.length === 0}
              configurationType={'githubRecommended'} // Mark as GitHub recommended
            />
          )}

          {customEnterpriseSecurityConfigurations.map((configuration, index) => (
            <SecurityConfigurationRow
              key={configuration.id}
              configuration={configuration}
              isFirst={!githubRecommendedConfiguration && index === 0}
              isLast={index === customEnterpriseSecurityConfigurations.length - 1}
              configurationType={'enterprise'}
            />
          ))}
        </div>
      </div>
    </>
  )
}

export default Configurations
