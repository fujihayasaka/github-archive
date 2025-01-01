import type {CuratedImageVersionDetailsPagePayload} from '../types/payloads'
import {Constants} from '../helpers/constants'
import {CuratedImageBreadcrumbs} from '../components/CuratedImageBreadcrumbs'
import {PageHeader} from '@primer/react'
import {pageHeadingStyle} from '../helpers/style'
import {CuratedImageVersionHeaderDescription} from '../components/CuratedImageVersionHeaderDescription'
import {useEffect} from 'react'
import {hostedComputeImageVersionDetailsRoute} from './hosted-compute-image-version-details-route'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'

export function CuratedImageVersionDetailsPageEntrypointFuture() {
  const {data: payload} = useRouteQuery(hostedComputeImageVersionDetailsRoute, 'mainQuery')
  return <CuratedImageVersionDetailsPage payload={payload} />
}

function CuratedImageVersionDetailsPage({payload}: {payload: CuratedImageVersionDetailsPagePayload}) {
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <>
      <PageHeader hasBorder className="mb-3" sx={pageHeadingStyle}>
        {Constants.stafftoolPageTitle}
      </PageHeader>
      <CuratedImageBreadcrumbs imageDefinition={payload.imageDefinition} imageVersion={payload.imageVersion} />
      <CuratedImageVersionHeaderDescription
        imageVersion={payload.imageVersion}
        imageDefinition={payload.imageDefinition}
      />
    </>
  )
}
