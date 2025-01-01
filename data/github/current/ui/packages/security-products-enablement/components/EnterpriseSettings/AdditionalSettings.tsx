import {ControlGroup} from '@github-ui/control-group'
import {Link as PrimerLink} from '@primer/react'
import ResourceLinks from './AdditionalSettings/SecretScanning/ResourceLinks'
import AIDetection from './AdditionalSettings/SecretScanning/AIDetection'
import UserNamespaceRepos from './AdditionalSettings/UserNamespaceRepos'
import {
  SecurityProductAvailability,
  type EnterpriseAdditionalSettings,
  type FlashParams,
} from '../../security-products-enablement-types'
import {useAppContext} from '../../contexts/AppContext'

export interface AdditionalSettingsProps {
  params: EnterpriseAdditionalSettings
  setFlashMessage: (flash: FlashParams) => void
}

const AdditionalSettings: React.FC<AdditionalSettingsProps> = ({params, setFlashMessage}) => {
  const {
    capabilities,
    docsUrls,
    securityProducts: {
      secret_scanning: {availability: secretScanningAvailability},
    },
  } = useAppContext()

  const secretScanning = (
    <div className="mb-4" data-testid="secret-scanning-additional-settings">
      <h4 className="mb-2">Secret Protection</h4>
      <div className="Subhead-description mb-3">
        These settings will only apply to repositories with Secret Protection enabled across all organizations in this
        enterprise.
      </div>

      <ControlGroup>
        <ResourceLinks value={params.resourceLink} />
        <AIDetection value={params.aiDetection} />
      </ControlGroup>
    </div>
  )

  const userNamespaceRepos = (
    <div data-testid="user-namespace-repos-additional-settings">
      <h4 className="mb-2">User namespace repositories</h4>
      <div className="Subhead-description mb-3">
        This section manages settings for repositories in user namespaces only. For all other types of repositories, use
        the configurations section above.{' '}
        {docsUrls.userOwnedRepos ? (
          <PrimerLink inline href={docsUrls.userOwnedRepos} target="_blank">
            Learn more about user namespace repositories.
          </PrimerLink>
        ) : (
          ''
        )}
      </div>
      <UserNamespaceRepos params={params} setFlashMessage={setFlashMessage} />
    </div>
  )

  const anythingToShow =
    secretScanningAvailability === SecurityProductAvailability.Available || capabilities.ghasForUserRepositories
  return anythingToShow ? (
    <div data-testid="additional-settings">
      <div className="Subhead">
        <h3 className="Subhead-heading h2-override-shared-component">Additional Settings</h3>
      </div>

      {secretScanningAvailability === SecurityProductAvailability.Available && secretScanning}
      {capabilities.ghasForUserRepositories && userNamespaceRepos}
    </div>
  ) : (
    <></>
  )
}

export default AdditionalSettings
