import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {settingsBusinessSecurityAnalysisConfigurationsNewPath} from '@github-ui/paths'
import {useAppContext} from '../../contexts/AppContext'
import SecurityConfigurationRow from '../SecurityConfiguration/Row'
import {AlphaLabel} from '@github-ui/lifecycle-labels/alpha'
import type {EnterpriseSettingsPayload} from '../../security-products-enablement-types'
import NewConfigurationButton from '../SecurityConfiguration/NewConfigurationButton'
import OrgFailuresBanner from './OrgFailuresBanner'

const Configurations: React.FC = () => {
  const {enterprise, githubRecommendedConfiguration, customEnterpriseSecurityConfigurations} = useAppContext()
  const {orgFailures} = useRoutePayload<EnterpriseSettingsPayload>()
  const enterprisePrivateBeta = useFeatureFlag('enterprise_security_configurations_private_beta_label')

  return (
    <>
      <div data-testid="enterprise-configurations" className="mb-5">
        <OrgFailuresBanner failures={orgFailures} />

        <div>
          <div className="d-flex flex-items-baseline">
            <div className="flex-1">
              <h3 className="Subhead-heading" style={{display: 'inline-flex', alignItems: 'center'}}>
                Configurations
                {enterprisePrivateBeta && (
                  <span style={{marginLeft: '8px'}}>
                    <AlphaLabel feedbackUrl="https://github.com/github-early-access/security-overview-private-beta-community/discussions/29" />
                  </span>
                )}
              </h3>
            </div>
            <NewConfigurationButton
              link={settingsBusinessSecurityAnalysisConfigurationsNewPath({business: enterprise?.slug || ''})}
            />
          </div>

          <div data-testid="subhead-description" className="Subhead-description mb-3">
            Define and apply security configurations to make sure your repositories are protected.
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
