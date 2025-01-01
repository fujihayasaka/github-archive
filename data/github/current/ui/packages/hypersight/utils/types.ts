import type {DiffLine} from '@github-ui/diffs/types'

export interface DiffHunk {
  hunkId: string
  filePath: string
  hunkTitle: string
  lines: DiffLine[]
  rawUnifiedDiff: string
  modificationType?: 'added' | 'deleted' | 'modified' | 'renamed'
}

export interface DiffGroup {
  title: string
  priority: 'low' | 'medium' | 'high'
  files: DiffFile[]
}

export type DiffGroupDescription =
  | {status: 'pending'}
  | {status: 'fetching'}
  | {status: 'error'; error: string}
  | {status: 'complete'; description: string}

/**
 * NEW interface representing a file that includes:
 * - filePath
 * - modificationType
 * - hunks relevant to that file
 */
export interface DiffFile {
  filePath: string
  modificationType: 'added' | 'deleted' | 'modified' | 'renamed'
  hunks: DiffHunk[]
}

export type WalkthroughGroups =
  | {status: 'pending'}
  | {status: 'fetching'}
  | {status: 'error'; error: string}
  | {status: 'complete'; diffGroupings: DiffGroup[]}

export interface GitHubUser {
  login: string
  id: number
  avatar_url: string
}

// Adding PullRequestSummaryState type to match what's used in PullRequestSummary.tsx
export type PullRequestSummaryState =
  | {status: 'pending'}
  | {status: 'fetching'}
  | {status: 'error'; error: string}
  | {status: 'complete'; summary: string}

export interface PullRequest {
  number: number
  title: string
  user: GitHubUser
  created_at: string
  updated_at: string
  state: 'open' | 'closed'
  html_url: string
  id: number
  body: string
  changed_files: number
  commits: number
  base: {
    ref: string
    repo: Repo
  }
  head: {
    ref: string
    repo: Repo
  }
}

export type HydratedIssueReference = {
  issueNumber: string
  title: string
  body: string
  repo: Repo
}

export type Repo = {
  name: string
  owner: {
    login: string
  }
}

export type Template = {
  name: string
  instructions: string
}

export interface DiffTreeEntry {
  mode: number
  path: string
  lineCount: number
  isGenerated?: boolean
}

export interface DiffData {
  diffLines: DiffLine[]
  isBinary: boolean
  isTooBig: boolean
  path: string
  status: 'ADDED' | 'DELETED' | 'MODIFIED' | 'RENAMED'
}

export interface NavigationUrls {
  conversation: string
  commits: string
  checks: string
  files: string
  walkthrough: string
}

export type Classification = {
  name: string
  description: string
}

export interface CAPIResponse {
  choices: CAPIChoice[]
  copilot_references?: CAPIReference[]
  id?: string
}

export interface CAPIChoice {
  delta: CAPIMessage
  finish_reason?: string
  message: CAPIMessage
}

export interface CAPIMessage {
  content: string
  role: string
}

export type FileCategory =
  | 'DOCUMENTATION'
  | 'CODE'
  | 'DATA'
  | 'DEPENDENCY_MANAGEMENT'
  | 'BINARY'
  | 'GENERATED'
  | 'TESTS'
  | 'VENDORED'
  | 'UNCATEGORIZED'

export type CodebaseQuestion = {
  question: string
  searchResults?: SearchResults
}

export interface SearchResultItem {
  name: string
  path: string
  html_url: string
  url: string
  contents?: string
  repository: {
    name: string
    full_name: string
  }
}

export interface SearchResults {
  total_count: number
  items: SearchResultItem[]
}

export interface CAPISnippetData {
  type: string
  path: string
  url: string
  repoName: string
  repoOwner: string
  contents?: string
  [key: string]: unknown // For other properties
}

export interface CAPIReference {
  type: string
  data?: CAPISnippetData
  id?: string
  is_implicit?: boolean
  metadata?: {
    display_name?: string
    display_icon?: string
    display_url?: string
  }
}

// Status type for UI updates
export type SearchInfo = {
  question: string
  totalResults: number
  topResults?: Array<{
    path: string
    url: string
  }>
}

type AnswerDeltaBase = {
  message: string
}

export type AnswerStatus = AnswerDeltaBase & {
  step: 'generating-questions' | 'searching-code' | 'generating-answer' | 'complete' | 'error'
  progress?: number // Optional progress indicator (0-100)
  details?: string // Optional additional details
  searches?: SearchInfo[] // Information about searches performed
  currentSearch?: SearchInfo // Current search being performed
}

export type AnswerPart = AnswerDeltaBase & {
  step: 'data'
}

export type AnswerProgress = AnswerStatus | AnswerPart

export type ExplanationDepth = 'None' | 'Light' | 'Balanced' | 'Moderate' | 'Full'
