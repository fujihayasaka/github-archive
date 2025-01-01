import {Link} from '@primer/react'
import type {ImageDefinition} from '../types/types'
import {featureFlagUrl} from '../helpers/urls'
import {ImageDefinitionGenericStatusIndicator} from './ImageDefinitionGenericStatusIndicator'

interface ImageDefinitionEnabledStateProps {
  imageDefinition: ImageDefinition
}

export function ImageDefinitionEnabledState(props: ImageDefinitionEnabledStateProps) {
  if (props.imageDefinition.featureFlag !== '') {
    return <Link href={featureFlagUrl(props.imageDefinition.featureFlag)}>Feature</Link>
  }

  return <ImageDefinitionGenericStatusIndicator value={props.imageDefinition.enabled} />
}
