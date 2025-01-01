import {addBaseFetchHeaders} from '@github-ui/fetch-headers'
// eslint-disable-next-line no-restricted-imports
import {remoteForm as originalRemoteForm, type RemoteFormHandler} from '@github/remote-form'

type Installable = string | HTMLFormElement

export function remoteForm(selector: Installable, fn: RemoteFormHandler) {
  originalRemoteForm(selector, async (form, kicker, req) => {
    addBaseFetchHeaders(req.headers)

    return fn(form, kicker, req)
  })
}

// eslint-disable-next-line no-barrel-files/no-barrel-files, no-restricted-imports
export {
  type Kicker,
  type SimpleRequest,
  type SimpleResponse,
  type ErrorWithResponse,
  afterRemote,
  beforeRemote,
} from '@github/remote-form'

// eslint-disable-next-line no-barrel-files/no-barrel-files
export type {RemoteFormHandler}
