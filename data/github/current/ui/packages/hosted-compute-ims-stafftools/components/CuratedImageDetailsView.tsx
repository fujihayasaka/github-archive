import type {ImageDefinition, ImageVersion} from '../types/types'
import {CuratedImageHeaderDescription} from './CuratedImageHeaderDescription'
import {CuratedImageVersionsTable} from './CuratedImageVersionsTable'

interface CuratedImageDetailsViewProps {
  curatedImage: ImageDefinition
  referencedImage?: ImageDefinition
  curatedImageVersions: ImageVersion[]
}

export function CuratedImageDetailsView(props: CuratedImageDetailsViewProps) {
  const isCuratedImagePointer = props.curatedImage.pointsToImageDefinitionId > 0
  return (
    <>
      <CuratedImageHeaderDescription curatedImage={props.curatedImage} referencedImage={props.referencedImage} />
      {!isCuratedImagePointer && (
        <CuratedImageVersionsTable
          curatedImageVersions={props.curatedImageVersions}
          curatedImage={props.curatedImage}
        />
      )}
    </>
  )
}
