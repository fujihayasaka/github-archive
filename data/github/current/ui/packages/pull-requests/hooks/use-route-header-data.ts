import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {FilesRoutePayload} from '../page-data/payloads/files'
import type {HeaderPageData} from '../page-data/payloads/header'
import type {CommitsRouteWithHeaderDataPayload} from '../routes/route-payload-types'

export function useRouteHeaderData(): HeaderPageData {
  const data = useRoutePayload<FilesRoutePayload | CommitsRouteWithHeaderDataPayload>()

  if (data && 'header' in data) {
    return data.header as HeaderPageData
  }

  const {aliveChannel, pullRequest, bannersData, repository, urls, user} = data

  return {aliveChannel, pullRequest, bannersData, repository, urls, user}
}
