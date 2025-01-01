import {Box, Link} from '@primer/react'
import type {ImageDefinition} from '../types/types'
import {ImageDefinitionEnabledState} from './ImageDefinitionEnabledState'
import {curatedImageDetailsUrl} from '../helpers/urls'
import {formatDateString} from '../helpers/utils'
import {useNavigate} from '@github-ui/use-navigate'
import {clickableLink} from '../helpers/style'
import {ImageDefinitionIsImageGenerationSupportedState} from './ImageDefinitionIsImageGenerationSupportedState'

interface CuratedImageHeaderDescriptionProps {
  curatedImage: ImageDefinition
  referencedImage?: ImageDefinition
}

export function CuratedImageHeaderDescription(props: CuratedImageHeaderDescriptionProps) {
  return (
    <Box
      sx={{
        borderTop: 'var(--borderWidth-thin) solid var(--borderColor-muted)',
        borderBottom: 'var(--borderWidth-thin) solid var(--borderColor-muted)',
        p: 2,
        mb: 3,
      }}
    >
      <div className="col-9 d-inline-block v-align-top">
        <div>
          <span className="color-fg-muted">Image Definition Id: </span>
          <span>{props.curatedImage.id}</span>
        </div>
        <div>
          <span className="color-fg-muted">Name: </span>
          <span>{props.curatedImage.name}</span>
        </div>
        <div>
          <span className="color-fg-muted">Owner: </span>
          <span>{props.curatedImage.ownerId}</span>
        </div>
        <div>
          <span className="color-fg-muted">Created At: </span>
          <span>{formatDateString(new Date(props.curatedImage.createdAt))}</span>
        </div>
        {props.curatedImage.pointsToImageDefinitionId ? (
          <div>
            <span className="color-fg-muted">Pointer For: </span>
            {ReferencedImageLink(props.curatedImage.pointsToImageDefinitionId, props.referencedImage)}
          </div>
        ) : null}
      </div>
      <div className="col-3 d-inline-block v-align-top">
        <div>
          <span className="color-fg-muted">OS Type: </span>
          <span>{props.curatedImage.osType}</span>
        </div>
        <div>
          <span className="color-fg-muted">Architecture: </span>
          <span>{props.curatedImage.architecture}</span>
        </div>
        <div>
          <span className="color-fg-muted">Enabled: </span>
          <span>
            <ImageDefinitionEnabledState imageDefinition={props.curatedImage} />
          </span>
        </div>
        <div>
          <span className="color-fg-muted">Image Gen Enabled: </span>
          <span>
            <ImageDefinitionIsImageGenerationSupportedState
              isImageGenerationSupported={props.curatedImage.isImageGenerationSupported}
            />
          </span>
        </div>
      </div>
    </Box>
  )
}

function ReferencedImageLink(
  referencedImageDefinitionId: number,
  referencedImage?: ImageDefinition,
): JSX.Element | null {
  const navigate = useNavigate()

  if (referencedImage) {
    return (
      <Link sx={clickableLink} onClick={() => navigate(curatedImageDetailsUrl(referencedImageDefinitionId))}>
        <span>
          {referencedImage.name} (ID {referencedImage.id})
        </span>
      </Link>
    )
  }

  return (
    <Link sx={clickableLink} onClick={() => navigate(curatedImageDetailsUrl(referencedImageDefinitionId))}>
      <span>Image ID {referencedImageDefinitionId}</span>
    </Link>
  )
}
