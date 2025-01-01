import type {PropertyDefinition} from '@github-ui/custom-properties-types'
import {businessOrgCustomPropertyDetailsPath, customPropertyDetailsPath} from '@github-ui/paths'

import {usePropertySource} from './use-property-source'

export function useNewPropertyPath() {
  const {pathPrefix, sourceName} = usePropertySource()
  return customPropertyDetailsPath({pathPrefix, sourceName})
}

export function useEditPropertyPath({propertyName, source}: PropertyDefinition) {
  const {pathPrefix, settingsLevel, sourceName} = usePropertySource()
  if (settingsLevel === 'org' || source.type === 'business') {
    return customPropertyDetailsPath({pathPrefix, sourceName, propertyName})
  } else {
    return businessOrgCustomPropertyDetailsPath({business: sourceName, org: source.slug, propertyName})
  }
}

export function useEditPropertyPathBuilder() {
  const {pathPrefix, sourceName} = usePropertySource()
  return (propertyName: string) => customPropertyDetailsPath({pathPrefix, sourceName, propertyName})
}
