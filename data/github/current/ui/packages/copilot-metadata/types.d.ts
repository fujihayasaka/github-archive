import type {AuthToken} from '@github-ui/copilot-auth-token/auth-token'

export type Collaborator = {
  id: number
  avatar_url: string
  username: string
  rank: string
  explanation: string
}

type MakeCAPIRequestRequestType = {
  basePath: string
  body: {messages: Array<{role: string; content: string}>; model: string; stream: boolean}
  path: string
  method: 'POST' | 'PATCH' | 'DELETE' | 'GET'
  streamingResponse: boolean
  authToken: AuthToken
  integrationId: string
}

export type MakeCAPIRequestType = (request: MakeCAPIRequestRequestType) => Promise<Response> | Promise<FailedAPIResult>

export type FileReference = {
  type: 'file' | 'file-v2'
  url: string
  path: string
  repoID: number
  repoOwner: string
  repoName: string
  ref: string
  commitOID: string
  languageName?: string
  languageId?: number
}
