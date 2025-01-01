import Subhead from '../components/Subhead'
import Configurations from '../components/EnterpriseSettings/Configurations'
import AdditionalSettings from '../components/EnterpriseSettings/AdditionalSettings'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {
  SecurityProductAvailability,
  type EnterpriseSettingsPayload,
  type FlashParams,
} from '../security-products-enablement-types'
import {useMemo, useState} from 'react'
import {getIcon} from '../utils/helpers'
import {Flash} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {useAppContext} from '../contexts/AppContext'
import BlankSlate from '../components/BlankSlate'
import {settingsBusinessSecurityAnalysisConfigurationsNewPath} from '@github-ui/paths'

import styles from './EnterpriseSettings.module.css'

const EnterpriseSettings: React.FC = () => {
  const {
    enterprise,
    securityProducts,
    docsUrls,
    githubRecommendedConfiguration,
    customEnterpriseSecurityConfigurations,
  } = useAppContext()

  const payload = useRoutePayload<EnterpriseSettingsPayload>()
  const [flashMessage, setFlashMessage] = useState<FlashParams>({})

  const allSecurityProductsUnavailable = Object.values(securityProducts).every(
    product => product.availability === SecurityProductAvailability.Unavailable,
  )

  const blankSlateProps = useMemo(() => {
    if (allSecurityProductsUnavailable) {
      return {
        header: 'No security features installed',
        message: 'Your GitHub Enterprise instance does not have any security features installed. ',
        url: docsUrls.installSecurityProducts,
        linkText: 'Learn about installing security features on GitHub Enterprise',
      }
    }

    if (customEnterpriseSecurityConfigurations.length === 0 && !githubRecommendedConfiguration) {
      return {
        header: 'Protect your code with Advanced Security configurations',
        message:
          'Enable and disable security features for specific repositories, ensure compliance, and manage your GitHub Advanced Security licenses with ',
        url: docsUrls.createConfig,
        linkText: 'security configurations',
        newConfigButtonPath: settingsBusinessSecurityAnalysisConfigurationsNewPath({business: enterprise?.slug || ''}),
      }
    }

    return null
  }, [
    allSecurityProductsUnavailable,
    customEnterpriseSecurityConfigurations.length,
    docsUrls.createConfig,
    docsUrls.installSecurityProducts,
    enterprise?.slug,
    githubRecommendedConfiguration,
  ])

  return (
    <div data-testid="enterprise-settings">
      {flashMessage.message && (
        <Flash variant={flashMessage.variant} className="mb-2">
          <Octicon icon={getIcon(flashMessage.variant)} />
          {flashMessage.message}
        </Flash>
      )}
      <Subhead heading={'h1'}>GitHub Advanced Security</Subhead>
      {blankSlateProps ? (
        <div className={styles.Box}>
          <BlankSlate {...blankSlateProps} />
        </div>
      ) : (
        <Configurations />
      )}
      <AdditionalSettings params={payload.additionalSettings} setFlashMessage={setFlashMessage} />
    </div>
  )
}

export default EnterpriseSettings
