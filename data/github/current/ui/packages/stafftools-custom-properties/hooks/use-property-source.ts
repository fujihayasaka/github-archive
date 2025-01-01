import {useLocation, useParams} from 'react-router-dom'
import {
  businessCustomPropertyDefinitionStafftoolsDetailsPath,
  businessCustomPropertyDefinitionStafftoolsListPath,
  orgCustomPropertiesDefinitionStafftoolsListPath,
  orgCustomPropertyDefinitionStafftoolsDetailsPath,
} from '../paths'

export function usePropertySource() {
  const {pathname} = useLocation()
  const {enterprise, org} = useParams()

  if (pathname.startsWith('/stafftools/enterprises') && enterprise) {
    return {
      sourceType: 'enterprise',
      listPath: businessCustomPropertyDefinitionStafftoolsListPath({enterprise}),
      detailsPathFromPropertyName: (propertyName: string) =>
        businessCustomPropertyDefinitionStafftoolsDetailsPath({enterprise, propertyName}),
    }
  } else if (pathname.startsWith('/stafftools/users') && org) {
    return {
      sourceType: 'organization',
      listPath: orgCustomPropertiesDefinitionStafftoolsListPath({org}),
      detailsPathFromPropertyName: (propertyName: string) =>
        orgCustomPropertyDefinitionStafftoolsDetailsPath({org, propertyName}),
    }
  } else {
    throw Error('Could not parse property source')
  }
}
