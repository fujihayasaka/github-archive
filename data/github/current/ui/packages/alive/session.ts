import {AliveSession as BaseAliveSession} from '@github/alive-client'
import type {AliveSessionOptions, Notifier} from '@github/alive-client'
export class AliveSession<T> extends BaseAliveSession<T> {
  private declare refreshUrl: string
  constructor(url: string, refreshUrl: string, shared: boolean, notify: Notifier<T>, options: AliveSessionOptions) {
    super(url, () => this.getUrlFromRefreshUrl(), shared, notify, undefined, options)
    this.refreshUrl = refreshUrl
  }

  private getUrlFromRefreshUrl() {
    return fetchRefreshUrl(this.refreshUrl)
  }
}

type PostUrl = {url?: string; token?: string}
async function fetchRefreshUrl(url: string): Promise<string | null> {
  const data = await fetchJSON<PostUrl>(url)
  return data && data.url && data.token ? post(data.url, data.token) : null
}

async function fetchJSON<T>(url: string): Promise<T | null> {
  const response = await fetch(url, {headers: {Accept: 'application/json'}})
  if (response.ok) {
    return response.json()
  } else if (response.status === 404) {
    return null
  } else {
    throw new Error('fetch error')
  }
}

async function post(url: string, csrf: string): Promise<string> {
  const response = await fetch(url, {
    method: 'POST',
    mode: 'same-origin',
    headers: {
      'Scoped-CSRF-Token': csrf,
    },
  })
  if (response.ok) {
    return response.text()
  } else {
    throw new Error('fetch error')
  }
}
