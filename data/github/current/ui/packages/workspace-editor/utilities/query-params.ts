import {addUrlToHistoryStack} from '@github-ui/history'

export const panelQueryParam = 'open_panel'
export const focusedTaskQueryParam = 'pull_request_review_comment_id'
export const initialPathQueryParam = 'initial_path'

export function removeQueryParam(param: string) {
  const url = new URL(window.location.href, window.location.origin)
  url.searchParams.delete(param)
  addUrlToHistoryStack(url.toString())
}

export function setQueryParam(param: string, value: string, setSearchParams?: (params: URLSearchParams) => void) {
  const url = new URL(window.location.href, window.location.origin)
  url.searchParams.set(param, value)
  if (setSearchParams) {
    setSearchParams(url.searchParams)
  } else {
    addUrlToHistoryStack(url.toString())
  }
}
