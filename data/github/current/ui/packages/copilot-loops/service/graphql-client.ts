import {reactFetchJSON} from '@github-ui/verified-fetch'
import {validateGraphQL} from '../utils/graphql'

export class GraphQLClient {
  readonly #graphqlApiUrl: string

  constructor(graphqlApiUrl: string) {
    this.#graphqlApiUrl = graphqlApiUrl
  }

  async getGraphQLResponse(query: string, signal?: AbortSignal) {
    const body = {
      query,
    }

    const response = await reactFetchJSON(this.#graphqlApiUrl, {
      method: 'POST',
      body,
      signal,
    })

    if (response.ok) {
      const responseJson = await response.json()
      const requestId = response.headers.get('X-Github-Request-Id') || ''
      if (validateGraphQL(responseJson, requestId)) {
        return responseJson
      }
    } else {
      throw new Error('Failed to get GraphQL response.')
    }
  }
}
