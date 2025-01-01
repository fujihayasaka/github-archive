export interface CustomCopilotRepositoryResource {
  /**This id is for the front end only */
  id: string
  databaseId?: number
  repositoryId: number
  nwo: string
  filePathFilters?: string
  markedForDestroy: boolean
  type: 'repository'
}

export interface CustomCopilotGitHubFileResource {
  /**This id is for the front end only */
  id: string
  databaseId?: number
  repositoryId: number
  nwo: string
  filePath: string
  markedForDestroy: boolean
  type: 'github_file'
}

export interface CustomCopilotFreeTextResource {
  /**This id is for the front end only */
  id: string
  databaseId?: number
  markedForDestroy: boolean
  type: 'free_text'
  text: string
  name: string
}

export type CustomCopilotResource =
  | CustomCopilotRepositoryResource
  | CustomCopilotGitHubFileResource
  | CustomCopilotFreeTextResource

export interface CustomCopilot {
  id: number
  name: string
  description: string
  resources: CustomCopilotResource[]
  generalInstructions: string
}

export interface CopilotChatRepo {
  id: number
  name: string
  ownerLogin: string
  ownerType: string
  readmePath: string | null
  description: string | null
  commitOID: string
  ref: string
  refInfo: {
    name: string
    type: string
  }
  visibility: string
  languages: string[]
  customInstructions: string | null
}

export interface GitHubFileFormData {
  id: string
  repositoryId: number
  nwo: string
  filePath: string
  type: 'github_file'
}
