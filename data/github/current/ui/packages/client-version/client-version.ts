import {ssrSafeWindow} from '@github-ui/ssr-utils'

const version = ssrSafeWindow?.document?.head?.querySelector<HTMLMetaElement>('meta[name="release"]')?.content || ''

export const CLIENT_VERSION_HTTP_HEADER = 'X-GitHub-Client-Version'

export function getClientVersion() {
  return version
}
