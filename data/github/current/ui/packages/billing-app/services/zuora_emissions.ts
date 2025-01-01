// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {EmissionDate} from '../types/zuora-emissions'

export const getZuoraEmissionsRequest = async (enterpriseSlug: string, emissionDate: EmissionDate) => {
  const url = `/stafftools/enterprises/${enterpriseSlug}/billing/zuora_emission?year=${emissionDate.year}&month=${emissionDate.month}&day=${emissionDate.day}`
  const response = await verifiedFetchJSON(url, {method: 'GET'})
  const data = await response.json()
  return {...data, statusCode: response.status}
}
