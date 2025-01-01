import type {CommitsPageData} from '../page-data/payloads/commits'
import type {HeaderPageData} from '../page-data/payloads/header'

export type LayoutRoutePayload = HeaderPageData

export type CommitsRouteWithHeaderDataPayload = CommitsPageData &
  HeaderPageData & {
    metadata: {
      deferredCommitsDataUrl: string
    }
  }

export type CommitsRoutePayload = CommitsPageData & {
  metadata: {
    deferredCommitsDataUrl: string
  }
}
