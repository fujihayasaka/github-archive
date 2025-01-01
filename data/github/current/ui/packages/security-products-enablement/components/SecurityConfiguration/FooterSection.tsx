import type React from 'react'
import {useNavigate} from '@github-ui/use-navigate'
import {InfoIcon} from '@primer/octicons-react'
import {Box, Button} from '@primer/react'
import {useAppContext} from '../../contexts/AppContext'
import DeleteButton from './DeleteButton'
import SaveButton from './SaveButton'
import {
  type NewRepositoryDefaults,
  type ValidationErrors,
  type SecurityConfigurationSettings,
  type FlashParams,
  type SecurityProductAvailability,
  SettingValue,
  type SecurityConfiguration,
  RenderContext,
} from '../../security-products-enablement-types'
import {useLocation} from 'react-router-dom'
import {scrollToTop} from '../../utils/helpers'
import {
  settingsBusinessSecurityAnalysisPath,
  settingsOrgSecurityProductsPath,
  settingsUserSecurityProductsPath,
} from '@github-ui/paths'

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
    capabilities: {ghasPurchased, ghasFreeForPublicRepos},
  } = useAppContext()

  // Remove the event listener to avoid memory leaks
  const clearState = () => {
    const newState = {...location.state}
    newState.flash = undefined
    window.history.replaceState(newState, '')
    window.removeEventListener('beforeunload', clearState)
  }

  const {dependabotAlertsVEA, codeScanning, secretScanning, enableGHAS} = securityConfigurationSettings
  const areGHASSettingsEnabled =
    dependabotAlertsVEA === SettingValue.Enabled ||
    codeScanning === SettingValue.Enabled ||
    secretScanning === SettingValue.Enabled

  const renderGHASMessage = (ghasPurchased && enableGHAS) || (ghasFreeForPublicRepos && areGHASSettingsEnabled)

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
    } else if (ghasPurchased) {
      return 'This configuration counts towards your GitHub Advanced Security license usage on private and internal repositories.'
    } else {
      return 'This configuration enables GitHub Advanced Security features. Applying it to private repositories will only enable free security features.'
    }
  }

  return (
    <div>
      <Box sx={{display: 'flex', flexDirection: 'row', justifyContent: 'space-between', gap: 2, my: 3}}>
        <Box sx={{display: 'flex', gap: 2}}>
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
        </Box>
        {!isNew && !isShow && (
          <DeleteButton
            securityConfiguration={securityConfiguration}
            clearState={clearState}
            setFlashMessage={setFlashMessage}
          />
        )}
      </Box>
      {renderGHASMessage && (
        <Box
          data-testid="info-text"
          sx={{display: 'flex', flexDirection: 'row', gap: 2, my: 2, alignItems: 'center', color: 'fg.muted'}}
        >
          <InfoIcon size={16} />
          <span>{ghasMessage()}</span>
        </Box>
      )}
    </div>
  )
}

export default SecurityConfigurationFooterSection
