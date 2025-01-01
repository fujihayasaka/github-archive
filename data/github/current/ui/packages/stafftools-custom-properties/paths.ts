export const orgCustomPropertyDefinitionStafftoolsDetailsPath = ({
  org,
  propertyName,
}: {
  org: string
  propertyName: string
}) => `/stafftools/users/${encodeURIComponent(org)}/organization_custom_properties/${encodeURIComponent(propertyName)}`

export const orgCustomPropertiesDefinitionStafftoolsListPath = ({org}: {org: string}) =>
  `/stafftools/users/${encodeURIComponent(org)}/organization_custom_properties`

export const businessCustomPropertyDefinitionStafftoolsDetailsPath = ({
  enterprise,
  propertyName,
}: {
  enterprise: string
  propertyName: string
}) => `/stafftools/enterprises/${encodeURIComponent(enterprise)}/custom_properties/${encodeURIComponent(propertyName)}`

export const businessCustomPropertyDefinitionStafftoolsListPath = ({enterprise}: {enterprise: string}) =>
  `/stafftools/enterprises/${encodeURIComponent(enterprise)}/custom_properties`
