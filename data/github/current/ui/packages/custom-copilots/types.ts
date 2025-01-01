interface CustomCopilotResourceBase {
  /** This id is for the front end only */
  id: string
  databaseId?: number
  sizePercentage?: number
  markedForDestroy: boolean
  type: string
}

export interface CustomCopilotGitHubFileResource extends CustomCopilotResourceBase {
  repositoryId: number
  nwo: string
  filePath: string
  fileExists: boolean
  type: 'github_file'
  commitish?: string
}

export interface CustomCopilotFreeTextResource extends CustomCopilotResourceBase {
  type: 'free_text'
  text: string
  name: string
}

export interface CustomCopilotGitHubIssueResource extends CustomCopilotResourceBase {
  type: 'github_issue'
  repositoryId: number
  number: number
  sizePercentage: number
  title: string
  url: string
  nwo: string
}

export interface CustomCopilotGitHubPullRequestResource extends CustomCopilotResourceBase {
  type: 'github_pull_request'
  repositoryId: number
  number: number
  sizePercentage: number
  title: string
  url: string
  nwo: string
}

export interface CustomCopilotUploadedTextFileResource extends CustomCopilotResourceBase {
  type: 'uploaded_text_file'
  name: string
  copilotChatAttachmentId: number
}

export type CustomCopilotResource =
  | CustomCopilotGitHubFileResource
  | CustomCopilotFreeTextResource
  | CustomCopilotGitHubIssueResource
  | CustomCopilotGitHubPullRequestResource
  | CustomCopilotUploadedTextFileResource

export type CopilotSpacesConfigPayload = {
  copilotSpacesConfig: {
    maxDescriptionLength: number
    maxGeneralInstructionsLength: number
    maxContentSize: number
  }
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
