import type React from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import {InfoIcon} from '@primer/octicons-react'
import {Button, Link as PrimerLink} from '@primer/react'
import {useAppContext} from '../../contexts/AppContext'
import DeleteButton from './DeleteButton'
import SaveButton from './SaveButton'
import {
  type NewRepositoryDefaults,
  type ValidationErrors,
  type SecurityConfigurationSettings,
  type FlashParams,
  type SecurityProductAvailability,
  type SecurityConfiguration,
  RenderContext,
} from '../../security-products-enablement-types'
import {useLocation} from 'react-router-dom'
import {arePaidFeaturesUsed, scrollToTop} from '../../utils/helpers'
import {
  settingsBusinessSecurityAnalysisPath,
  settingsOrgSecurityProductsPath,
  settingsUserSecurityProductsPath,
} from '@github-ui/paths'
import {updateCurrentState} from '@github-ui/history'

import styles from './FooterSection.module.css'

interface SecurityConfigurationFooterSectionProps {
  isNew: boolean
  isShow: boolean
  securityConfigurationSettings: SecurityConfigurationSettings
  securityConfiguration?: SecurityConfiguration
  configurationName: React.RefObject<HTMLInputElement>
  configurationDescription: React.RefObject<HTMLInputElement>
  newRepoDefaults?: NewRepositoryDefaults
  tip: string
  updateErrors: (errors: ValidationErrors) => void
  setFlashMessage: (flash: FlashParams) => void
  isAvailable: (availability: SecurityProductAvailability) => boolean
}

const SecurityConfigurationFooterSection: React.FC<SecurityConfigurationFooterSectionProps> = ({
  isNew,
  isShow,
  securityConfigurationSettings,
  securityConfiguration,
  configurationName,
  configurationDescription,
  newRepoDefaults,
  tip,
  updateErrors,
  setFlashMessage,
  isAvailable,
}) => {
  const navigate = useNavigate()
  const location = useLocation()
  const {
    renderContext,
    organization,
    enterprise,
    capabilities: {ghasFreeForPublicRepos, advancedSecurity},
    docsUrls,
  } = useAppContext()

  // Remove the event listener to avoid memory leaks
  const clearState = () => {
    const newState = {...location.state}
    newState.flash = undefined
    updateCurrentState(newState)
    window.removeEventListener('beforeunload', clearState)
  }

  const {enableGHAS, enableSecretProtection, enableCodeSecurity} = securityConfigurationSettings

  let renderGHASMessage: boolean
  if (renderContext === RenderContext.User) {
    renderGHASMessage = false
  } else if (advancedSecurity.purchased) {
    renderGHASMessage = enableGHAS
  } else if (ghasFreeForPublicRepos) {
    renderGHASMessage = arePaidFeaturesUsed(securityConfigurationSettings)
  } else {
    renderGHASMessage = false
  }

  const renderPaidSKUMessage =
    (advancedSecurity.purchased || ghasFreeForPublicRepos) && (enableSecretProtection || enableCodeSecurity)

  const handleCancelConfigClick = () => {
    const path = () => {
      switch (renderContext) {
        case RenderContext.Enterprise:
          return settingsBusinessSecurityAnalysisPath({business: enterprise!.slug})
        case RenderContext.Organization:
          return settingsOrgSecurityProductsPath({org: organization})
        case RenderContext.User:
          return settingsUserSecurityProductsPath()
        default:
          return ''
      }
    }

    navigate(path())
    scrollToTop()
  }

  const ghasMessage = () => {
    if (!ghasFreeForPublicRepos) {
      return 'This configuration counts towards your GitHub Advanced Security license usage.'
    } else if (advancedSecurity.purchased) {
      return 'This configuration counts towards your GitHub Advanced Security license usage on private and internal repositories.'
    } else {
      return 'This configuration enables GitHub Advanced Security features. Applying it to private repositories will only enable free security features.'
    }
  }

  const skuMessage = (): JSX.Element => {
    let enabledProducts = ''

    if (enableSecretProtection && enableCodeSecurity) {
      enabledProducts = 'Secret Protection and Code Security'
    } else if (enableSecretProtection) {
      enabledProducts = 'Secret Protection'
    } else if (enableCodeSecurity) {
      enabledProducts = 'Code Security'
    }

    let applicableRepos = ''
    if (ghasFreeForPublicRepos) {
      applicableRepos = 'Private and internal repositories'
    } else {
      applicableRepos = 'Repositories'
    }

    return (
      <>
        {applicableRepos} with this configuration applied are subject to {enabledProducts} license usage.{' '}
        <PrimerLink inline href={docsUrls.ghasBilling} target="_blank">
          Learn more about Advanced Security billing.
        </PrimerLink>
      </>
    )
  }

  return (
    <div>
      <div className={styles.Box}>
        <div className={styles.Box_1}>
          <SaveButton
            isShow={isShow}
            isNew={isNew}
            securityConfigurationSettings={securityConfigurationSettings}
            securityConfiguration={securityConfiguration}
            configurationName={configurationName}
            configurationDescription={configurationDescription}
            newRepoDefaults={newRepoDefaults}
            tip={tip}
            updateErrors={updateErrors}
            setFlashMessage={setFlashMessage}
            isAvailable={isAvailable}
            clearState={clearState}
          />
          <Button variant="default" onClick={() => handleCancelConfigClick()}>
            Cancel
          </Button>
        </div>
        {!isNew && !isShow && (
          <DeleteButton
            securityConfiguration={securityConfiguration}
            clearState={clearState}
            setFlashMessage={setFlashMessage}
          />
        )}
      </div>
      {advancedSecurity.bundled && renderGHASMessage && (
        <div data-testid="info-text" className={styles.Box_2}>
          <InfoIcon size={16} />
          <span>{ghasMessage()}</span>
        </div>
      )}
      {!advancedSecurity.bundled && renderPaidSKUMessage && (
        <div data-testid="sku-info-text" className={styles.Box_2}>
          <InfoIcon size={16} />
          <span>{skuMessage()}</span>
        </div>
      )}
    </div>
  )
}

export default SecurityConfigurationFooterSection
