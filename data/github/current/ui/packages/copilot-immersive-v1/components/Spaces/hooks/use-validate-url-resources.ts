import type {
  CustomCopilotGitHubIssueResource,
  CustomCopilotGitHubPullRequestResource,
} from '@github-ui/custom-copilots/types'
import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

export class UrlDetails {
  url: string
  owner: string
  repo: string
  number: number
  type: UrlType
  id: string
  errorMessage?: string

  constructor(id: string, url = '', owner = '', repo = '', number = 0, type: UrlType = 'unknown') {
    this.id = id
    this.url = url
    this.owner = owner
    this.repo = repo
    this.number = number
    this.type = type
  }
}

export type UrlResourceValidationError = {
  id: string
  errors: Record<string, string>
}

type UrlType = 'github_pull_request' | 'github_issue' | 'unknown'

function resourceMetadataToRailsPayload(resource: UrlDetails) {
  switch (resource.type) {
    case 'github_issue':
    case 'github_pull_request':
      return {
        owner: resource.owner,
        repo: resource.repo,
        number: resource.number,
      }
    default:
      throw new Error(`Unsupported resource`)
  }
}

export const useValidateUrlResources = () => {
  const {mutateAsync: validateUrlResources, ...rest} = useMutation({
    mutationFn: async ({input, spaceOwner}: {input: UrlDetails[]; spaceOwner: string | undefined}) => {
      const url = `/copilot/spaces/validate_url_resources`
      const method = 'POST'

      const body = {
        // eslint-disable-next-line camelcase
        resources_attributes: input.map(r => ({
          id: r.id,
          // eslint-disable-next-line camelcase
          resource_type: r.type,
          metadata: resourceMetadataToRailsPayload(r),
        })),
        // eslint-disable-next-line camelcase
        space_owner: spaceOwner,
      }

      const response = await verifiedFetchJSON(url, {
        method,
        body,
      })

      const data = await response.json()
      if (!response.ok) {
        throw data
      }

      return data as Array<CustomCopilotGitHubPullRequestResource | CustomCopilotGitHubIssueResource>
    },
  })

  return {
    validateUrlResources,
    ...rest,
  }
}
