import {ImageDefinitionGenericStatusIndicator} from './ImageDefinitionGenericStatusIndicator'

interface ImageDefinitionIsImageGenerationSupportedProps {
  isImageGenerationSupported: boolean
}

export function ImageDefinitionIsImageGenerationSupportedState(props: ImageDefinitionIsImageGenerationSupportedProps) {
  return <ImageDefinitionGenericStatusIndicator value={props.isImageGenerationSupported} />
}
