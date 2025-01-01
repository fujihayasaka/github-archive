import type {ImageDefinition, ImageVersion} from './types'
import type {SelectedImagesTab} from '../helpers/urls'

export interface MainPagePayload {
  imageDefinitions: ImageDefinition[]
  selectedImagesTab: SelectedImagesTab
}

export interface CuratedImageDetailsPagePayload {
  imageDefinition: ImageDefinition
  referencedImageDefinition?: ImageDefinition
  imageVersions: ImageVersion[]
}

export interface CuratedImageVersionDetailsPagePayload {
  imageDefinition: ImageDefinition
  imageVersion: ImageVersion
  nonResolvedVersion: string
}
