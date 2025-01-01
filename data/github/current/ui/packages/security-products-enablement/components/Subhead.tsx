import {settingsOrgSecurityConfigurationsNewPath, settingsUserSecurityConfigurationsNewPath} from '@github-ui/paths'
import type React from 'react'
import NewConfigurationButton from './SecurityConfiguration/NewConfigurationButton'
import {useAppContext} from '../contexts/AppContext'

interface SubheadProps {
  children: React.ReactNode
  organization?: string
  newConfigButton?: boolean
  description?: string
  allSecurityProductsUnavailable?: boolean
}

const Subhead: React.FC<SubheadProps> = ({
  children,
  description,
  organization,
  allSecurityProductsUnavailable,
  newConfigButton = false,
}) => {
  const {renderContext} = useAppContext()

  const link =
    renderContext === 'organization' && organization
      ? settingsOrgSecurityConfigurationsNewPath({org: organization})
      : settingsUserSecurityConfigurationsNewPath()

  return (
    <>
      <div className={'Subhead'}>
        <h2 className="Subhead-heading">{children}</h2>
        {!allSecurityProductsUnavailable && newConfigButton && <NewConfigurationButton link={link} />}
      </div>
      {description && (
        <div data-testid="subhead-description" className="Subhead-description mb-3">
          {description}
        </div>
      )}
    </>
  )
}

export default Subhead
