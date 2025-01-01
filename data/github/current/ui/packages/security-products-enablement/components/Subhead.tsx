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
  heading?: React.ElementType
}

const Subhead: React.FC<SubheadProps> = ({
  children,
  description,
  organization,
  allSecurityProductsUnavailable,
  newConfigButton = false,
  heading: Heading = 'h2',
}) => {
  const {renderContext} = useAppContext()

  const link =
    renderContext === 'organization' && organization
      ? settingsOrgSecurityConfigurationsNewPath({org: organization})
      : settingsUserSecurityConfigurationsNewPath()

  return (
    <>
      <div className={'Subhead'}>
        <Heading className="Subhead-heading h1-override-shared-component">{children}</Heading>
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
