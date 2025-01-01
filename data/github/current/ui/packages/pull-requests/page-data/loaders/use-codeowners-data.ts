import {useCallback} from 'react'
import {useQuery, useSuspenseQuery, type QueryKey} from '@github-ui/react-query'
import {reactFetch} from '@github-ui/verified-fetch'
import {reportTraceData} from '@github-ui/internal-api-insights'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import type {Codeowners, CodeownersPathOwnership} from '../payloads/codeowners'

function codeownersKey(basePath: string): QueryKey {
  return [PageData.codeowners, basePath]
}

// TODO use usePageDataUrl, when hook is always called from a child component of PageDataContextProvider
export function codeownersApiUrl(basePath: string): string {
  return `${basePath}/page_data/${PageData.codeowners}`
}

function codeownersPayload(basePath: string) {
  return {
    queryKey: codeownersKey(basePath),
    queryFn: async () => {
      const apiUrl = codeownersApiUrl(basePath)
      const result = await reactFetch(apiUrl)
      if (!result.ok) throw new Error(`HTTP ${result.status}`)

      const json = await result.json()
      reportTraceData(json)
      return json
    },
    staleTime: Infinity,
  }
}

/*
 * Returns all ownership data from the CODEOWNERS file
 */
export function useCodeowners({basePath, initialData}: {basePath: string; initialData?: Codeowners}) {
  const {queryFn, queryKey} = codeownersPayload(basePath)
  return useQuery<Codeowners>({
    queryKey,
    queryFn,
    initialData,
    staleTime: Infinity,
  })
}

/*
 * Returns ownership data from the CODEOWNERS file for the given path
 *   - If codeowners data is not available, returns default ownership (unowned)
 *   - If path doesn't have an associated CODEOWNERS rule, returns default ownership (unowned)
 */
export function usePathOwnership({basePath, diffPath}: {basePath: string; diffPath: string}) {
  const {queryFn, queryKey} = codeownersPayload(basePath)
  return useSuspenseQuery({
    queryKey,
    queryFn,
    staleTime: Infinity,
    select: useCallback((data?: Codeowners) => getPathOwnership({codeownersData: data, diffPath}), [diffPath]),
  })
}

const defaultOwnership: CodeownersPathOwnership = {
  isOwnedByViewer: false,
  owners: [],
  ruleLineNumber: undefined,
  ruleUrl: undefined,
}

export function getPathOwnership({
  diffPath,
  codeownersData,
}: {
  diffPath: string
  codeownersData?: Codeowners
}): CodeownersPathOwnership {
  if (!codeownersData) return defaultOwnership

  const pathInfo = codeownersData.ownershipByPath[diffPath]
  if (!pathInfo) return defaultOwnership

  return {
    isOwnedByViewer: pathInfo.isOwnedByViewer,
    owners: pathInfo.owners || [],
    ruleLineNumber: pathInfo.ruleLineNumber,
    ruleUrl: pathInfo.ruleUrl,
  }
}
