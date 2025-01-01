import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

export interface CommitsSelectorCommitData {
  actorLogin: string
  createdAt: string
  messageHeadline: string
  oid: string
  shortOid: string
}

export type FileTreePayload = {
  baseRefOid: string
  commits: CommitsSelectorCommitData[]
  lastReviewOid?: string
  ownerLogin: string
  pathName: string
  pullRequestId: string
  pullRequestNumber: number
  repositoryName: string
}

export type ThreadMarker = {
  id: number
  start?: string
}

export type AnnotationMarker = {
  id: number
}

export type DiffMarkers = {
  threads: ThreadMarker[]
  annotations: AnnotationMarker[]
}

export type PullRequestFileTreeDiff = DiffDelta & {
  isCodeowner?: boolean
  isManifestFile?: boolean
  isVendored?: boolean
  markedAsViewed?: boolean
  linesChanged: number
  linesAdded: number
  linesDeleted: number
  markersMap?: {
    [markerPosition: string]: DiffMarkers
  }
}
