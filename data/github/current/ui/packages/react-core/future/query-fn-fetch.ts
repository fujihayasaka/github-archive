import {reactFetchJSON, type JSONRequestInit} from '@github-ui/verified-fetch'
import {ResponseError} from './response-error'
import {reportTraceData} from '@github-ui/internal-api-insights'

type QueryFnPartialQueryKey = {
  queryDeps: {
    pathname: string
    searchParams?:
      | ConstructorParameters<typeof URLSearchParams>[0]
      | Record<string, string | null>
      | Array<[string, string | null]>
    init?: JSONRequestInit
  }
}

/**
 * Intended for use by `queryFn`s that need to make fetch requests.
 * In addition to calling `reactFetchJSON` to add the appropriate react headers to the request,
 * this function will also check the response status and throw a `ResponseError` if necessary,
 * as well as hooking into `reportTraceData`.
 */
export async function queryFnFetch<Response>({queryDeps: {pathname, searchParams, init}}: QueryFnPartialQueryKey) {
  const path = serializePath(pathname, searchParams)

  const response = await reactFetchJSON(path, init)
  if (!response.ok) {
    throw new ResponseError(response.statusText, response)
  }

  const json = (await response.json()) as Response
  reportTraceData(json)
  return json
}

/**
 * Serializes the given `pathname` and `searchParams` to a string.
 */
function serializePath(pathname: string, searchParams?: QueryFnPartialQueryKey['queryDeps']['searchParams']) {
  const path = [pathname]
  const search = removeNils(searchParams).toString()
  if (search) {
    path.push(search.toString())
  }
  return path.join('?')
}

/**
 * Removes any search-params with a value of `null` or `undefined` from the given `searchParams` object.
 * This is necessary as we construct `queryDeps.searchParams` with code like `{page: searchParams.get('page')}`,
 * which will result in a value of `null` if the key is not present in the `searchParams` object and
 * URLSeachParams.toString() will serialize `null` values as the string "null", which is not the desired behavior.
 */
function removeNils(searchParams: QueryFnPartialQueryKey['queryDeps']['searchParams']): URLSearchParams {
  if (searchParams instanceof URLSearchParams) {
    return searchParams
  }
  if (typeof searchParams === 'string') {
    return new URLSearchParams(searchParams)
  }

  const result = new URLSearchParams()
  if (searchParams === undefined || searchParams === null) {
    return result
  }
  for (const [key, value] of Array.isArray(searchParams) ? searchParams : Object.entries(searchParams)) {
    if (value !== undefined && value !== null) {
      result.append(key, value)
    }
  }
  return result
}
