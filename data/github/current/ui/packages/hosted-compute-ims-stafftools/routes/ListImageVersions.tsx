import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {ImageDefinition, ImageVersion} from '../types/types'
import {Constants} from '../helpers/constants'
import {CuratedImageVersionsTable} from '../components/CuratedImageVersionsTable'
import {BreadcrumbsHeading} from '../components/BreadCrumbsHeading'
import {homepagePath} from '../helpers/paths'

export interface ListImageVersionsPayload {
  imageDefinition: ImageDefinition
  imageVersions: ImageVersion[]
}

export function ListImageVersions() {
  const payload = useRoutePayload<ListImageVersionsPayload>()

  return (
    <>
      <BreadcrumbsHeading
        previousPageLink={homepagePath()}
        previousPageTitle={Constants.curatedImagesTabTitle}
        currentPageTitle={`${payload.imageDefinition.name} (ID ${payload.imageDefinition.id})`}
      />
      <CuratedImageVersionsTable imageVersions={payload.imageVersions} imageDefinition={payload.imageDefinition} />
    </>
  )
}
