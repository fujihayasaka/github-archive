import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import type {CAPIResponse, CAPISnippetData, SearchResultItem, SearchResults} from './types'

export async function searchCode(url: string, owner: string, repo: string, query: string): Promise<SearchResults> {
  try {
    const basePath = url
    const copilotAuthTokenProvider = new CopilotAuthTokenProvider([])
    const token = await copilotAuthTokenProvider.getAuthToken()
    const headers: {[key: string]: string} = {
      Authorization: token.authorizationHeaderValue,
      'copilot-integration-id': 'playground-dev',
      'Content-Type': 'application/json',
    }
    const payload = {
      messages: [
        {
          role: 'user',
          copilot_references: [
            {
              type: 'github.searchInputs',
              data: {
                type: 'search-inputs',
                id: 0,
                depth: 0,
                task: String(query), // Ensure query is a primitive string
                owner: String(owner), // Ensure owner is a primitive string
                repositoryName: String(repo), // Ensure repo is a primitive string
                includeTextRefs: false,
              },
            },
          ],
          name: 'question',
        },
      ],
    }

    // Make the fetch request
    const signal = null
    const response = await fetch(`${basePath}/agents/github-search-agent`, {
      method: 'POST',
      mode: 'cors',
      cache: 'no-cache',
      headers,
      body: JSON.stringify(payload),
      signal,
    })

    if (!response.ok) {
      const text = await response.text()
      const hdr = response.headers
      throw new Error(`GitHub search failed with status: ${response.status} ${text} ${hdr}`)
    }

    const text = await response.text()
    const results = parseSearchResponse(text)

    return sanitizeSearchResults(results)
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error in searchCode:', error)
    return {total_count: 0, items: []}
  }
}

/**
 * Sanitizes a search result item to prevent circular references
 * by creating a new clean object with only the necessary properties.
 */
function sanitizeSearchItem(item: SearchResultItem): SearchResultItem {
  return {
    name: String(item.name || ''),
    path: String(item.path || ''),
    html_url: String(item.html_url || ''),
    url: String(item.url || ''),
    contents: item.contents ? String(item.contents) : undefined,
    repository: {
      name: String(item.repository?.name || ''),
      full_name: String(item.repository?.full_name || ''),
    },
  }
}

/**
 * Sanitizes a search results to prevent circular references
 * by creating a new clean object with only the necessary properties.
 */
function sanitizeSearchResults(results: SearchResults): SearchResults {
  return {
    total_count: results.total_count || 0,
    items: Array.isArray(results.items) ? results.items.map(item => sanitizeSearchItem(item)) : [],
  }
}

/**
 * Parses the response text, extracting **all** valid JSON lines
 * that begin with `data:` and merging any discovered snippet references.
 */
function parseSearchResponse(text: string): SearchResults {
  try {
    // Split lines, trim, and filter out "[DONE]" chunks
    const lines = text.split('\n')
    const dataLines = lines.map(line => line.trim()).filter(line => line.startsWith('data:') && line !== 'data: [DONE]')

    if (!dataLines.length) {
      // eslint-disable-next-line no-console
      console.error('No valid JSON data found in response')
      return {total_count: 0, items: []}
    }

    // Accumulate items
    const allItems: SearchResultItem[] = []

    for (const line of dataLines) {
      // Strip off 'data:' prefix, parse JSON if possible
      const jsonStr = line.replace(/^data:\s*/, '').trim()
      if (!jsonStr) continue

      try {
        const parsedData = JSON.parse(jsonStr) as CAPIResponse

        const snippets = parsedData.copilot_references ?? []
        const snippetItems: SearchResultItem[] = snippets
          .filter(ref => ref.type === 'github.snippet' && ref.data)
          .map(ref => {
            const data = ref.data as CAPISnippetData
            const filename = data.path.split('/').pop() ?? ''

            return {
              name: filename,
              path: data.path,
              contents: data.contents,
              html_url: data.url,
              url: data.url,
              repository: {
                name: data.repoName,
                full_name: `${data.repoOwner}/${data.repoName}`,
              },
            }
          })

        // Merge into our total item list
        allItems.push(...snippetItems)
      } catch (parseError) {
        // eslint-disable-next-line no-console
        console.error('Error parsing JSON from response line:', parseError)
      }
    }

    return {total_count: allItems.length, items: allItems}
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error parsing search response:', error)
    return {total_count: 0, items: []}
  }
}
