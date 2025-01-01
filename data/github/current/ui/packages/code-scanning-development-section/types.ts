export type PullRequestData = {
  type: 'pull_request'
  baseRefName: string
  baseRefUrl: string
  closedAt: string | null
  createdAt: string
  isDraft: boolean
  mergedAt: string | null
  number: number
  state: PullRequestState
  title: string
  url: string
}

export type PullRequestState = 'CLOSED' | 'MERGED' | 'OPEN'

// This is the minimal set of keys we need to display the row in the ItemPicker
export type PullRequestPickerData = Pick<PullRequestData, 'type' | 'title' | 'number' | 'state'> & {
  merged: boolean
  draft: boolean
}

export type BranchData = {
  type: 'branch'
  lastModifiedAt: string
  name: string
  url: string
}

// This is the minimal set of keys we need to display the row in the ItemPicker
export type BranchPickerData = Pick<BranchData, 'type' | 'name'>

export type SearchResult = PullRequestPickerData | BranchPickerData

export type SearchResults = {
  results: SearchResult[]
}

export type DevelopmentSectionRepository = {
  id: number
  name: string
  ownerLogin: string
  path: string
}
