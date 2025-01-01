export type PathParams = Record<string, string | number> | undefined
export type PathFunction<T extends PathParams | void = void> = (args: T) => string
export type Query = Record<string, string | number | boolean | null | undefined>

export type Repository = {
  name: string
  ownerLogin: string
}

export type ActivityFilter = {
  actor?: {
    login: string
  }
  activityType: string
  timePeriod: string
  sort: string
}

export type RepositoryTreePathAction =
  | 'tree'
  | 'blob'
  | 'blame'
  | 'raw'
  | 'new'
  | 'edit'
  | 'delete'
  | 'upload'
  | 'tree/delete'
  | 'latest-commit'
  | 'tree-commit-info'
  | 'branch-infobar'
  | 'file-contributors'
  | 'overview-files'

export type RepositoryPathAction =
  | 'hovercard'
  | 'refs'
  | 'actions'
  | 'pulls'
  | 'issues'
  | 'issues/new'
  | 'branches'
  | 'tags'
  | 'settings'

export type ModelUrlable = {registry: string; name: string}
