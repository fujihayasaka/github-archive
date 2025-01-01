import type {DiffLine} from '@github-ui/diff-lines'
import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useMutation, useQuery, useQueryClient, type QueryKey} from '@github-ui/react-query'
import {reactFetch} from '@github-ui/verified-fetch'

export type ContextLineRange = {
  start: number
  end: number
}

export type ContextLineResponse = {
  // TODO remove diffEntryWithContext and make diffEntryLines required when :react_diff_line_type_character_correction
  // feature flag is graduated
  diffEntryWithContext?: DiffLine[]
  diffEntryLines?: DiffLine[]
}

export function diffContextLinesKey(basePath: string, path: string): QueryKey {
  return [PageData.diffContextLines, basePath, path]
}

export function useDiffLinesIncludingContext(basePath: string, path: string, initialData?: DiffLine[]) {
  const queryKey = diffContextLinesKey(basePath, path)

  return useQuery<DiffLine[]>({
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : []
    },
    initialData,
    staleTime: Infinity,
  })
}

export function useFetchMoreContextLines(basePath: string, path: string) {
  const contextLinesKey = diffContextLinesKey(basePath, path)
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (variables: {contextLineRanges: ContextLineRange[]; url: string; path: string}) => {
      const responseBody = await fetchInjectedContextLines(variables.contextLineRanges, variables.url, variables.path)

      queryClient.setQueryData(contextLinesKey, (old: DiffLine[]) => {
        // TODO use responseBody?.diffEntryLines only when :react_diff_line_type_character_correction feature flag is graduated
        const diffEntryLines = responseBody?.diffEntryWithContext ?? responseBody?.diffEntryLines
        return mergeContextLines(old, diffEntryLines ?? [])
      })
      return
    },
  })
}

function getRangesAsSeparateURLParams(contextLineRanges: ContextLineRange[]) {
  let returnString = ''
  for (let i = 0; i < contextLineRanges.length; i++) {
    returnString += `&context_line_ranges[]=${JSON.stringify(contextLineRanges[i])}`
  }
  return returnString
}
/**
 * Fetches the context lines for a given diff entry
 */
async function fetchInjectedContextLines(
  contextLineRanges: ContextLineRange[],
  url: string,
  path: string,
): Promise<ContextLineResponse | undefined> {
  const baseFetchUrl = `${url}?path=${path}${getRangesAsSeparateURLParams(contextLineRanges)}`
  const response = await reactFetch(baseFetchUrl)

  if (response.ok) {
    const data = await response.json()
    return data ?? undefined
  }
}

export function mergeContextLines(initialDiffLines: DiffLine[], expandedDiffLines: DiffLine[]) {
  const lineMap = new Map<string, (typeof initialDiffLines)[0]>()

  for (const line of initialDiffLines) {
    const key = `${line.left}-${line.right}`
    lineMap.set(key, line)
  }

  // using a map for lookups is faster than using a `find` on the array while iterating through the map
  const mergedDiffLines = expandedDiffLines.map(line => {
    const key = `${line.left}-${line.right}`
    const existingLine = lineMap.get(key)

    if (existingLine) {
      return {...line, position: existingLine.position, displayNoNewLineWarning: existingLine.displayNoNewLineWarning}
    } else {
      // diffLines don't actually care about position and we can't comment on context lines anyway
      return {...line, position: null, threadsData: undefined}
    }
  })

  return mergedDiffLines
}
