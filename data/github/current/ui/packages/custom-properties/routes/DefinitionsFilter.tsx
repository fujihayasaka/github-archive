import {Filter, FilterProviderType} from '@github-ui/filter'
import {OrgFilterProvider, StaticFilterProvider} from '@github-ui/filter/providers'
import {singleFilterProviderOption} from '@github-ui/filter/utils'
import {BriefcaseIcon, GlobeIcon, OrganizationIcon} from '@primer/octicons-react'

export function DefinitionsFilter({
  filterValue,
  onChange,
  onSubmit,
  businessSlug,
  className,
}: {
  filterValue: string
  onChange: (value: string) => void
  onSubmit: (query: string) => void
  businessSlug: string
  className?: string
}) {
  return (
    <Filter
      id="properties-filter"
      label="Filter properties"
      className={className}
      providers={[
        new ManagedByFilterProvider(),
        new OrgFilterProvider({
          filterTypes: {valueless: false, exclusive: false},
          businessSlug,
        }),
      ]}
      filterValue={filterValue}
      onChange={onChange}
      onSubmit={request => onSubmit(request.raw)}
    />
  )
}

class ManagedByFilterProvider extends StaticFilterProvider {
  constructor() {
    const filter = {
      displayName: 'Managed by',
      key: 'managed-by',
      description: 'Include properties managed by the enterprise and/or any of its organizations',
      priority: 1,
      icon: BriefcaseIcon,
    }

    const values = [
      {value: 'enterprise', displayName: 'Enterprise', icon: GlobeIcon, priority: 1},
      {value: 'organization', displayName: 'Organization', icon: OrganizationIcon, priority: 2},
    ]

    super(filter, values, {filterTypes: {...singleFilterProviderOption.filterTypes, exclusive: false}})
    this.type = FilterProviderType.Select
  }
}
