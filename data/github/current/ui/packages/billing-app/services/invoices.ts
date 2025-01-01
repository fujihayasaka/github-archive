import {verifiedFetchJSON} from '@github-ui/verified-fetch'

import type {GenerateInvoiceRequest} from '../types/invoices'

export const generateInvoiceRequest = async (
  slug: string,
  payload: GenerateInvoiceRequest,
  accountType: string,
): Promise<Record<string, never>> => {
  const url = `/stafftools/${accountType}/${slug}/billing/invoices`
  const response = await verifiedFetchJSON(url, {method: 'POST', body: payload})
  const data = await response.json()

  return {...data, statusCode: response.status}
}

export const getInvoicesRequest = async (slug: string, customerId: string, accountType: string) => {
  const url = `/stafftools/${accountType}/${slug}/billing/invoices?customer_id=${customerId}`
  const response = await verifiedFetchJSON(url, {method: 'GET'})
  const data = await response.json()
  return {...data, statusCode: response.status}
}
