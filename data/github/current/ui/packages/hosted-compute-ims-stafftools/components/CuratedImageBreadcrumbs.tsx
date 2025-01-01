import {Box, Breadcrumbs} from '@primer/react'
import {Spacing, clickableLink} from '../helpers/style'
import {useNavigate} from '@github-ui/use-navigate'
import type {ImageDefinition, ImageVersion} from '../types/types'
import {Constants} from '../helpers/constants'
import {curatedImageDetailsUrl, rootUrl} from '../helpers/urls'
import {getLastUrlSegment} from '../helpers/utils'

interface CuratedImageBreadcrumbsProps {
  imageDefinition: ImageDefinition
  imageVersion?: ImageVersion
}

export function CuratedImageBreadcrumbs(props: CuratedImageBreadcrumbsProps) {
  const navigate = useNavigate()

  let imageDefinitionsListTitle: string = ''
  let imageDefinitionListUrl: string = ''
  if (props.imageDefinition.pointsToImageDefinitionId > 0) {
    imageDefinitionsListTitle = Constants.pointersImagesTabTitle
    imageDefinitionListUrl = rootUrl('pointers')
  } else if (props.imageDefinition.ownerId === 'github') {
    imageDefinitionsListTitle = Constants.githubOwnedImagesTabTitle
    imageDefinitionListUrl = rootUrl('github-images')
  } else if (props.imageDefinition.ownerId === 'partner') {
    imageDefinitionsListTitle = Constants.partnerOwnedImagesTabTitle
    imageDefinitionListUrl = rootUrl('partner-images')
  } else if (props.imageDefinition.ownerId === 'azuredevops') {
    imageDefinitionsListTitle = Constants.azureDevOpsImagesTabTitle
    imageDefinitionListUrl = rootUrl('azuredevops-images')
  }

  const imageDefinitionTitle = `${props.imageDefinition.name} (ID ${props.imageDefinition.id})`

  const breadcrumbsItems = [
    <Breadcrumbs.Item key="image_definition" sx={clickableLink} onClick={() => navigate(imageDefinitionListUrl)}>
      {imageDefinitionsListTitle}
    </Breadcrumbs.Item>,
  ]

  if (props.imageVersion) {
    const imageVersionTitle = getLastUrlSegment() === 'latest' ? 'Latest' : props.imageVersion.version
    breadcrumbsItems.push(
      <Breadcrumbs.Item sx={clickableLink} onClick={() => navigate(curatedImageDetailsUrl(props.imageDefinition.id))}>
        {imageDefinitionTitle}
      </Breadcrumbs.Item>,
      <Breadcrumbs.Item selected>{imageVersionTitle}</Breadcrumbs.Item>,
    )
  } else {
    breadcrumbsItems.push(<Breadcrumbs.Item selected>{imageDefinitionTitle}</Breadcrumbs.Item>)
  }

  return (
    <Box sx={{mb: Spacing.StandardPadding}}>
      <Breadcrumbs>{...breadcrumbsItems}</Breadcrumbs>
    </Box>
  )
}
