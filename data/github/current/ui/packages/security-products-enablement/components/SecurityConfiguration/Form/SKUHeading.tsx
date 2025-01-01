import {ActionMenu, ActionList} from '@primer/react'
import {useAppContext} from '../../../contexts/AppContext'
import {useSecuritySettingsContext} from '../../../contexts/SecuritySettingsContext'
import {isShowOnly} from '../../../utils/helpers'
import type {SecurityConfigurationSettingsAction} from '../../../utils/security-configuration-reducer'
import BlankSlate from '../../BlankSlate'

interface SKUHeadingProps {
  sku: string
  dispatchSettings: React.Dispatch<{type: SecurityConfigurationSettingsAction; sku: string}>
}

const SKUHeading: React.FC<SKUHeadingProps> = ({sku, dispatchSettings}) => {
  const {
    capabilities: {ghasFreeForPublicRepos, advancedSecurity},
    securityConfiguration,
    renderContext,
    docsUrls,
  } = useAppContext()
  const {enableSecretProtection, enableCodeSecurity} = useSecuritySettingsContext()
  const isShow = isShowOnly(securityConfiguration, renderContext)

  const billingText = ghasFreeForPublicRepos
    ? 'Free for public repositories and billed per 90-day active committer for private and internal repositories.'
    : 'Billed per 90-day active committer for all repositories.'

  let enabled = false
  let humanSKUName = ''
  let purchased = false
  switch (sku) {
    case 'secret_protection':
      humanSKUName = 'Secret Protection'
      enabled = enableSecretProtection
      purchased = advancedSecurity.secretProtectionPurchased
      break
    case 'code_security':
      humanSKUName = 'Code Security'
      enabled = enableCodeSecurity
      purchased = advancedSecurity.codeSecurityPurchased
      break
    default:
      humanSKUName = sku
  }
  /* m2 (8px) is too little, m3 (16px) is too much so we have to use an inline style here */
  const label = <span style={{marginRight: '13px'}}>{enabled ? 'Enabled' : 'Disabled'}</span>

  const handleSelect = (value: string) => {
    const type = value === 'enable' ? 'ENABLE_SKU_SETTINGS' : 'DISABLE_SKU_SETTINGS'
    dispatchSettings({type, sku})
  }

  const dropdown = (
    <ActionMenu>
      <ActionMenu.Button>{label}</ActionMenu.Button>
      <ActionMenu.Overlay width="medium">
        <ActionList selectionVariant="single">
          <ActionList.Item selected={enabled} onSelect={() => handleSelect('enable')}>
            Enabled
            <ActionList.Description variant="block">
              Enable GitHub {humanSKUName} features for this configuration.
            </ActionList.Description>
          </ActionList.Item>
          <ActionList.Item selected={!enabled} onSelect={() => handleSelect('disable')}>
            Disabled
            <ActionList.Description variant="block">
              Disable GitHub {humanSKUName} features for this configuration.
            </ActionList.Description>
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  )

  return (
    <>
      <div className="d-flex flex-items-center" data-testid={`${sku}_sku_heading`}>
        <div className="flex-1">
          <h3>{humanSKUName}</h3>
          <p className="color-fg-muted">{billingText}</p>
        </div>
        <div className="flex-2">{isShow ? label : dropdown}</div>
      </div>
      {!ghasFreeForPublicRepos && !purchased && (
        <div className="mb-3">
          <BlankSlate
            header={`${humanSKUName} is not purchased`}
            message=""
            linkText={`Learn more about ${humanSKUName}`}
            url={docsUrls.aboutGHAS}
          />
        </div>
      )}
    </>
  )
}

export default SKUHeading
