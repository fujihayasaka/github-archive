import type {FilterProps, FilterProvider} from '@github-ui/filter'
import {Filter, FilterProviderType} from '@github-ui/filter'
import {OrgFilterProvider, StaticFilterProvider} from '@github-ui/filter/providers'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {
  BriefcaseIcon,
  CheckboxIcon,
  CheckCircleIcon,
  GlobeIcon,
  KeyAsteriskIcon,
  MultiSelectIcon,
  NoteIcon,
  OrganizationIcon,
  QuestionIcon,
  SingleSelectIcon,
  TypographyIcon,
} from '@primer/octicons-react'
import {useMemo} from 'react'

interface Props extends Omit<FilterProps, 'providers' | 'id' | 'label'> {
  businessSlug?: string
}

export function DefinitionsFilter({filterValue, onChange, onSubmit, businessSlug, className, variant}: Props) {
  const showRequiredDefinitionFilter = useFeatureFlag('custom_property_definitions_required_filter')

  const providers = useMemo(() => {
    const providersList: FilterProvider[] = [new ManagedByFilterProvider(), new PropertyTypeFilterProvider()]

    if (showRequiredDefinitionFilter) providersList.push(new RequiredFilterProvider())

    if (businessSlug) {
      providersList.push(
        new OrgFilterProvider({
          filterTypes: {valueless: false, exclusive: true},
          businessSlug,
        }),
      )
    }
    return providersList
  }, [businessSlug, showRequiredDefinitionFilter])

  return (
    <Filter
      id="properties-filter"
      label="Filter properties"
      className={className}
      providers={providers}
      filterValue={filterValue}
      onChange={onChange}
      onSubmit={onSubmit}
      variant={variant}
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

    super(filter, values, {filterTypes: {multiKey: false, multiValue: true, valueless: false, exclusive: true}})
    this.type = FilterProviderType.Select
  }
}

class PropertyTypeFilterProvider extends StaticFilterProvider {
  constructor() {
    const filter = {
      displayName: 'Property type',
      key: 'value-type',
      description: 'Filter definitions by type',
      priority: 1,
      icon: NoteIcon,
    }

    const values = [
      {value: 'text', displayName: 'Text', icon: TypographyIcon, priority: 1},
      {value: 'single_select', displayName: 'Single select', icon: SingleSelectIcon, priority: 2},
      {value: 'multi_select', displayName: 'Multi select', icon: MultiSelectIcon, priority: 3},
      {value: 'true_false', displayName: 'True/false', icon: CheckboxIcon, priority: 4},
    ]

    super(filter, values, {filterTypes: {multiKey: false, multiValue: true, valueless: false, exclusive: true}})
    this.type = FilterProviderType.Select
  }
}

class RequiredFilterProvider extends StaticFilterProvider {
  constructor() {
    const filter = {
      displayName: 'Required',
      key: 'required',
      description: 'Filter definitions by whether they are required or optional',
      priority: 1,
      icon: KeyAsteriskIcon,
    }

    const values = [
      {value: 'true', displayName: 'True', icon: CheckCircleIcon, priority: 1},
      {value: 'false', displayName: 'False', icon: QuestionIcon, priority: 2},
    ]

    super(filter, values, {filterTypes: {multiKey: false, multiValue: false, valueless: false, exclusive: true}})
    this.type = FilterProviderType.Select
  }
}
