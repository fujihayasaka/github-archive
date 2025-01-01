import {wait} from '@github-ui/eventloop-tasks'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

interface CommitQuorumCheckResponse {
  data: {
    hasQuorum: boolean
  }
}

interface CommitQuorumCheckErrorResponse {
  statusText: string
}

async function fetchCommitQuorumCheckJSON(url: string): Promise<boolean | CommitQuorumCheckErrorResponse> {
  const response = await verifiedFetchJSON(url)
  if (response.ok) {
    const json = (await response.json()) as CommitQuorumCheckResponse
    return json.data.hasQuorum
  } else {
    return {statusText: response.statusText}
  }
}

/**
 * Polls the given URL with backoff until the commit has quorum
 * or until the max number of retries is reached
 * This allows us to check if git has quorum before redirecting
 * @param url - The URL to poll for commit availability
 * @returns A promise that resolves when the commit has quorum, the max number of retries is reached, or an error occurs
 */
export async function pollUntilCommitHasQuorum(url: string): Promise<void> {
  let hasQuorum = false
  let retries = 0

  try {
    while (hasQuorum === false && retries < 3) {
      const commitQuorumCheckResponse = await fetchCommitQuorumCheckJSON(`${url}?attempt_number=${retries + 1}`)

      if (typeof commitQuorumCheckResponse === 'boolean') {
        hasQuorum = hasQuorum || commitQuorumCheckResponse

        if (!hasQuorum) {
          retries++
          await wait(retries * 1000) // wait and poll with backoff 1s, 2s, 3s
        }
      } else {
        // if the response is not a boolean, it's an error and we should stop polling
        break
      }
    }
  } catch {
    // swallow any errors - this polling is a QOL improvemment
    // and shouldn't block the redirecting to the quickpull if it fails
  }
}
