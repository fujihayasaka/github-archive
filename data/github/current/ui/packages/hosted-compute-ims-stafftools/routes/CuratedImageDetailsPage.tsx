import type {CuratedImageDetailsPagePayload} from '../types/payloads'
import {Constants} from '../helpers/constants'
import {CuratedImageBreadcrumbs} from '../components/CuratedImageBreadcrumbs'
import {PageHeader} from '@primer/react'
import {pageHeadingStyle} from '../helpers/style'
import {CuratedImageDetailsView} from '../components/CuratedImageDetailsView'
import {useEffect} from 'react'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {hostedComputeImageDetailsRoute} from './hosted-compute-image-details-route'

export function CuratedImageDetailsPageEntrypointFuture() {
  const {data: payload} = useRouteQuery(hostedComputeImageDetailsRoute, 'mainQuery')
  return <CuratedImageDetailsPage payload={payload} />
}

function CuratedImageDetailsPage({payload}: {payload: CuratedImageDetailsPagePayload}) {
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <>
      <PageHeader hasBorder className="mb-3" sx={pageHeadingStyle}>
        {Constants.stafftoolPageTitle}
      </PageHeader>
      <CuratedImageBreadcrumbs imageDefinition={payload.imageDefinition} />
      <CuratedImageDetailsView
        curatedImage={payload.imageDefinition}
        referencedImage={payload.referencedImageDefinition}
        curatedImageVersions={payload.imageVersions}
      />
    </>
  )
}
