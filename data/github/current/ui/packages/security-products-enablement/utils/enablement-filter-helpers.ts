import {
  FilterProviderType,
  type FilterKey,
  type FilterProvider,
  type FilterSuggestion,
  type SuppliedFilterProviderOptions,
} from '@github-ui/filter'
import {StaticFilterProvider} from '@github-ui/filter/providers'
import {ShieldIcon, DependabotIcon, CodescanIcon, KeyIcon} from '@primer/octicons-react'
import type {Capabilities, SecurityProducts} from '../security-products-enablement-types'
import {SecurityProductAvailability} from '../security-products-enablement-types'

const ENABLEMENT_STATUS_VALUES = [
  {value: 'enabled', displayName: 'Enabled', priority: 1},
  {value: 'disabled', displayName: 'Disabled', priority: 1},
]

const CODE_SCANNING_ENABLEMENT_VALUES = [
  {value: 'enabled', displayName: 'Enabled', priority: 1},
  {value: 'eligible', displayName: 'Eligible', priority: 1},
  {value: 'not-eligible', displayName: 'Not eligible', priority: 1},
]

const GHAS_ENABLEMENT = {
  displayName: 'GitHub Advanced Security',
  key: 'advanced-security',
  description: '',
  priority: 2,
  icon: ShieldIcon,
}

const DEPENDABOT_ALERTS_ENABLEMENT = {
  displayName: 'Dependabot alerts',
  key: 'dependabot-alerts',
  description: '',
  priority: 2,
  icon: DependabotIcon,
}

const DEPENDABOT_SECURITY_UPDATES_ENABLEMENT = {
  displayName: 'Dependabot security updates',
  key: 'dependabot-security-updates',
  description: '',
  priority: 2,
  icon: DependabotIcon,
}

const CODE_SCANNING_ALERTS_ENABLEMENT = {
  displayName: 'Code scanning alerts',
  key: 'code-scanning-alerts',
  description: '',
  priority: 2,
  icon: CodescanIcon,
}

const CODE_SCANNING_DEFAULT_SETUP_ENABLEMENT = {
  displayName: 'Code scanning default setup',
  key: 'code-scanning-default-setup',
  description: '',
  priority: 2,
  icon: CodescanIcon,
}

const SECRET_SCANNING_ALERTS_ENABLEMENT = {
  displayName: 'Secret scanning alerts',
  key: 'secret-scanning-alerts',
  description: '',
  priority: 2,
  icon: KeyIcon,
}

const PUSH_PROTECTION_ENABLEMENT = {
  displayName: 'Push protection',
  key: 'secret-scanning-push-protection',
  description: '',
  priority: 2,
  icon: KeyIcon,
}

export class ValuesFilterProvider extends StaticFilterProvider {
  constructor(filter: FilterKey, values: FilterSuggestion[], options?: SuppliedFilterProviderOptions) {
    super(filter, values, options)
    this.type = values.length === 0 ? FilterProviderType.Text : FilterProviderType.Select
  }
}

export const comma: SuppliedFilterProviderOptions = {
  filterTypes: {multiKey: false, multiValue: true, valueless: false, exclusive: false},
}

export const createEnablementStatusProviders = (
  capabilities: Capabilities,
  securityProducts: SecurityProducts,
): FilterProvider[] => {
  const createSecurityProductProvider = (
    filter: FilterKey,
    values: FilterSuggestion[],
    availabilityCheck: (filter: FilterKey) => boolean,
  ): FilterProvider | null => {
    return availabilityCheck(filter) ? new ValuesFilterProvider(filter, values, comma) : null
  }

  const productAvailabilityCheck = (
    availability: SecurityProductAvailability,
    requiresGhasOrEnterprise: boolean = false,
  ) => {
    return (
      availability === SecurityProductAvailability.Available &&
      (!requiresGhasOrEnterprise || capabilities.advancedSecurity.purchased || capabilities.enterpriseOwned)
    )
  }

  const isFilterAvailable = (filter: FilterKey): boolean => {
    switch (filter) {
      case GHAS_ENABLEMENT:
        return (
          capabilities.advancedSecurity.bundled &&
          (capabilities.advancedSecurity.purchased || capabilities.enterpriseOwned)
        )
      case DEPENDABOT_ALERTS_ENABLEMENT:
        return productAvailabilityCheck(securityProducts.dependabot_alerts.availability)
      case DEPENDABOT_SECURITY_UPDATES_ENABLEMENT:
        return productAvailabilityCheck(securityProducts.dependabot_updates.availability)
      case CODE_SCANNING_ALERTS_ENABLEMENT:
      case CODE_SCANNING_DEFAULT_SETUP_ENABLEMENT:
        return productAvailabilityCheck(securityProducts.code_scanning.availability, true)
      case SECRET_SCANNING_ALERTS_ENABLEMENT:
      case PUSH_PROTECTION_ENABLEMENT:
        return productAvailabilityCheck(securityProducts.secret_scanning.availability, true)
      default:
        return capabilities.advancedSecurity.purchased || capabilities.enterpriseOwned
    }
  }

  return [
    createSecurityProductProvider(GHAS_ENABLEMENT, ENABLEMENT_STATUS_VALUES, isFilterAvailable),
    createSecurityProductProvider(DEPENDABOT_ALERTS_ENABLEMENT, ENABLEMENT_STATUS_VALUES, isFilterAvailable),
    createSecurityProductProvider(DEPENDABOT_SECURITY_UPDATES_ENABLEMENT, ENABLEMENT_STATUS_VALUES, isFilterAvailable),
    createSecurityProductProvider(CODE_SCANNING_ALERTS_ENABLEMENT, ENABLEMENT_STATUS_VALUES, isFilterAvailable),
    createSecurityProductProvider(
      CODE_SCANNING_DEFAULT_SETUP_ENABLEMENT,
      CODE_SCANNING_ENABLEMENT_VALUES,
      isFilterAvailable,
    ),
    createSecurityProductProvider(SECRET_SCANNING_ALERTS_ENABLEMENT, ENABLEMENT_STATUS_VALUES, isFilterAvailable),
    createSecurityProductProvider(PUSH_PROTECTION_ENABLEMENT, ENABLEMENT_STATUS_VALUES, isFilterAvailable),
  ].filter(Boolean) as FilterProvider[]
}
