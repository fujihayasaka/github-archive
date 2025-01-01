import {useState, type MouseEvent} from 'react'
import {ControlGroup} from '@github-ui/control-group'
import BulkActions from './UserNamespaceRepos/BulkActions'
import {
  SecurityProductAvailability,
  type EnterpriseAdditionalSettings,
  type FlashParams,
} from '../../../security-products-enablement-types'
import {bulkToggleUserNamespaceEnablement} from '../../../utils/api-helpers'
import {useAppContext} from '../../../contexts/AppContext'

export interface UserNamespaceReposProps {
  params: EnterpriseAdditionalSettings
  setFlashMessage: (flash: FlashParams) => void
}

const UserNamespaceRepos: React.FC<UserNamespaceReposProps> = ({params, setFlashMessage}) => {
  const {enterprise, securityProducts} = useAppContext()
  const [advancedSecurityNewRepos, setAdvancedSecurityNewRepos] = useState<boolean>(
    params.advancedSecurityEnabledNewRepos || false,
  )
  const [secretScanningNewRepos, setSecretScanningNewRepos] = useState<boolean>(
    params.secretScanningEnabledNewRepos || false,
  )
  const [pushProtectionNewRepos, setPushProtectionNewRepos] = useState<boolean>(
    params.pushProtectionEnabledNewRepos || false,
  )

  const toggleSetting = async (
    currentState: boolean,
    setState: React.Dispatch<React.SetStateAction<boolean>>,
    setting: string,
  ) => {
    const newValue = !currentState
    setState(newValue)
    const toggle = newValue ? 'enabled' : 'disabled'
    await bulkToggleUserNamespaceEnablement(enterprise!.slug, {setting, toggle})
  }

  return (
    <ControlGroup>
      <BulkActions setFlashMessage={setFlashMessage} />
      <ControlGroup.Item>
        <ControlGroup.Title id="github-advanced-security">
          Automatically enable GitHub Advanced Security for new user namespace repositories
        </ControlGroup.Title>
        <ControlGroup.ToggleSwitch
          aria-label="GitHub Advanced Security"
          checked={advancedSecurityNewRepos}
          onClick={(e: MouseEvent<HTMLButtonElement>) => {
            e.preventDefault()
            toggleSetting(advancedSecurityNewRepos, setAdvancedSecurityNewRepos, 'advanced_security_enabled_new_repos')
          }}
        />
      </ControlGroup.Item>
      {securityProducts.secret_scanning.availability === SecurityProductAvailability.Available ? (
        <>
          <ControlGroup.Item>
            <ControlGroup.Title id="secret-scanning">
              Automatically enable secret scanning for new user namespace repositories with GitHub Advanced Security
            </ControlGroup.Title>
            <ControlGroup.ToggleSwitch
              aria-label="Secret scanning"
              checked={secretScanningNewRepos}
              onClick={(e: MouseEvent<HTMLButtonElement>) => {
                e.preventDefault()
                toggleSetting(secretScanningNewRepos, setSecretScanningNewRepos, 'secret_scanning_new_repos')
              }}
            />
          </ControlGroup.Item>
          <ControlGroup.Item>
            <ControlGroup.Title id="push-protection">
              Automatically enable push protection for new user namespace repositories with GitHub Advanced Security
            </ControlGroup.Title>
            <ControlGroup.ToggleSwitch
              aria-label="Push protection"
              checked={pushProtectionNewRepos}
              onClick={(e: MouseEvent<HTMLButtonElement>) => {
                e.preventDefault()
                toggleSetting(
                  pushProtectionNewRepos,
                  setPushProtectionNewRepos,
                  'secret_scanning_push_protection_new_repos',
                )
              }}
            />
          </ControlGroup.Item>
        </>
      ) : (
        ''
      )}
    </ControlGroup>
  )
}

export default UserNamespaceRepos
