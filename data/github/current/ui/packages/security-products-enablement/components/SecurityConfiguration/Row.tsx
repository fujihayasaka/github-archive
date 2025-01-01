import type React from 'react'
import capitalize from 'lodash-es/capitalize'
import pluralize from 'pluralize'
import {Link as PrimerLink, IconButton} from '@primer/react'
import {Link} from '@github-ui/react-core/link'
import {
  settingsBusinessSecurityAnalysisConfigurationsEditPath,
  settingsBusinessSecurityAnalysisConfigurationsViewPath,
  settingsOrgSecurityConfigurationsEditPath,
  settingsOrgSecurityConfigurationsViewPath,
  settingsOrgSecurityProductsPath,
  settingsUserSecurityConfigurationsEditPath,
  settingsUserSecurityConfigurationsViewPath,
} from '@github-ui/paths'
import {RenderContext, type OrganizationSecurityConfiguration} from '../../security-products-enablement-types'
import {useAppContext} from '../../contexts/AppContext'
import ApplyToButton from './ApplyToButton'
import RowLabel from '../RowLabel'
import {PencilIcon} from '@primer/octicons-react'
import {getEscapedFilterValue} from '@github-ui/filter/utils'

interface SecurityConfigurationRowProps {
  configuration: OrganizationSecurityConfiguration
  isLast: boolean
  isFirst?: boolean
  configurationType: string
  confirmConfigApplication?: (
    config: OrganizationSecurityConfiguration,
    overrideExistingConfig: boolean,
    applyToAll: boolean,
  ) => void
}

const SecurityConfigurationRow: React.FC<SecurityConfigurationRowProps> = ({
  configuration,
  isLast,
  isFirst = false,
  configurationType,
}) => {
  const {organization, enterprise, capabilities, renderContext} = useAppContext()
  const {
    default_for_new_private_repos,
    default_for_new_public_repos,
    id,
    name,
    enable_ghas,
    enforcement,
    description,
    repositories_count,
  } = configuration

  // Determine the link path based on whether it's a GitHub recommended configuration or not
  let linkPath
  if (renderContext === RenderContext.Organization) {
    linkPath =
      configurationType === 'githubRecommended' || configurationType === 'enterprise'
        ? settingsOrgSecurityConfigurationsViewPath({org: organization, id})
        : settingsOrgSecurityConfigurationsEditPath({org: organization, id})
  } else if (renderContext === RenderContext.Enterprise) {
    linkPath =
      configurationType === 'githubRecommended'
        ? settingsBusinessSecurityAnalysisConfigurationsViewPath({business: enterprise!.slug, id})
        : settingsBusinessSecurityAnalysisConfigurationsEditPath({business: enterprise!.slug, id})
  } else {
    linkPath = ''
  }

  switch (renderContext) {
    case RenderContext.Enterprise:
      linkPath =
        configurationType === 'githubRecommended'
          ? settingsBusinessSecurityAnalysisConfigurationsViewPath({business: enterprise!.slug, id})
          : settingsBusinessSecurityAnalysisConfigurationsEditPath({business: enterprise!.slug, id})
      break
    case RenderContext.Organization:
      linkPath =
        configurationType === 'githubRecommended' || configurationType === 'enterprise'
          ? settingsOrgSecurityConfigurationsViewPath({org: organization, id})
          : settingsOrgSecurityConfigurationsEditPath({org: organization, id})
      break
    case RenderContext.User:
      linkPath =
        configurationType === 'githubRecommended'
          ? settingsUserSecurityConfigurationsViewPath({id})
          : settingsUserSecurityConfigurationsEditPath({id})
      break
  }

  let boxClassNames = `border-x border-bottom py-3 px-3`
  if (isFirst) boxClassNames = `${boxClassNames} rounded-top-2 border-top`
  if (isLast) boxClassNames = `${boxClassNames} rounded-bottom-2`

  const getDefaultText = () => {
    if (default_for_new_private_repos && default_for_new_public_repos) {
      return 'Default for all new repositories.'
    } else if (default_for_new_private_repos) {
      return 'Default for new private and internal repositories.'
    } else {
      return 'Default for new public repositories.'
    }
  }

  const configurationNameFilterURL = () => {
    const escapedValue = getEscapedFilterValue(configuration.name)
    const searchQuery = `configuration:${escapedValue}`
    return `${settingsOrgSecurityProductsPath({org: organization})}?q=${searchQuery}`
  }

  const repoCounts = () => {
    if (renderContext === RenderContext.Enterprise) {
      // We do not support linking to repo counts on the Enterprise page:
      return pluralize('repository', repositories_count, true)
    } else if (renderContext === RenderContext.Organization) {
      // We are setting reloadDocument=true to trigger a turbo nav since we don't support react routing
      // for the filter string:
      return (
        <PrimerLink as={Link} to={configurationNameFilterURL()} reloadDocument className="color-fg-muted">
          {pluralize('repository', repositories_count, true)}
        </PrimerLink>
      )
    } else {
      return ''
    }
  }

  return (
    <div className={boxClassNames} data-testid={`configuration-${id}`}>
      <div className="d-flex flex-items-center">
        <div className="text-bold mb-1 flex-1">
          <PrimerLink as={Link} to={linkPath} sx={{color: 'fg.default'}} data-testid={`configuration-${id}-name`}>
            {name.length > 0 ? name : 'unnamed security configuration'}
          </PrimerLink>
          {enable_ghas && capabilities.ghasPurchased && <RowLabel text="GitHub Advanced Security" />}
          {enforcement === 'enforced' && <RowLabel text={capitalize(enforcement)} />}
          <div className="f6 color-fg-muted text-normal" data-testid={`configuration-${id}-description`}>
            {description}{' '}
            {(default_for_new_private_repos || default_for_new_public_repos) && (
              <span className="text-bold">{getDefaultText()}</span>
            )}
          </div>
        </div>
        <div className="f6 m-3 color-fg-muted flex-2" data-testid={`configuration-${id}-repositories-count`}>
          {repoCounts()}
        </div>
        <ApplyToButton configuration={configuration} />
        <PrimerLink as={Link} to={linkPath} sx={{ml: 2, color: 'fg.default'}} aria-label={`Edit ${name}`}>
          <IconButton icon={PencilIcon} aria-label={`Edit ${name}`} />
        </PrimerLink>
      </div>
    </div>
  )
}

export default SecurityConfigurationRow
