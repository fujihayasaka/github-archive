import type {FileDiffReference, FileReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {DiffEntry} from '../types'
import type {Repository} from '@github-ui/current-repository'
import {repositoryTreePath} from '@github-ui/paths'

export type CopilotChatDiffEntry = Pick<
  DiffEntry,
  | 'isBinary'
  | 'isSubmodule'
  | 'path'
  | 'status'
  | 'newCommitOid'
  | 'newTreeEntry'
  | 'oldCommitOid'
  | 'oldTreeEntry'
  | 'pathDigest'
> & {
  repository: Pick<Repository, 'id' | 'name' | 'ownerLogin'>
}

export const isValidForCopilotChat = ({
  hasCopilotAccess,
  isBinary,
  isSubmodule,
  path,
  repository,
  status,
}: Pick<CopilotChatDiffEntry, 'isBinary' | 'isSubmodule' | 'path' | 'status' | 'repository'> & {
  hasCopilotAccess: boolean
}) => {
  // eventually we'll want to handle LFS and files > 1mb when it becomes a real problem
  // skipping right now to reduce gitrpc calls for a (presumably) rare scenario
  if (!hasCopilotAccess) return false
  if (isBinary || isSubmodule) return false
  if (!path) return false
  if (status === 'DELETED' || status === 'REMOVED') return false
  if (!repository.id || !repository.name || !repository.ownerLogin) return false

  return true
}

export const generateCopilotChatReference = ({
  newCommitOid,
  newTreeEntry,
  oldCommitOid,
  oldTreeEntry,
  path,
  pathDigest,
  repository,
}: Pick<
  CopilotChatDiffEntry,
  'newCommitOid' | 'newTreeEntry' | 'oldCommitOid' | 'oldTreeEntry' | 'path' | 'pathDigest' | 'repository'
>): FileDiffReference => {
  const referenceRawUrl =
    oldCommitOid && newCommitOid
      ? repositoryTreePath({
          repo: repository,
          commitish: oldCommitOid,
          action: 'raw',
          path,
        })
      : ''

  return {
    baseFile: generateFileReference({path: oldTreeEntry?.path, oid: oldCommitOid, repository}),
    headFile: generateFileReference({path: newTreeEntry?.path, oid: newCommitOid, repository}),
    baseBranchRef: oldCommitOid,
    id: `#diff-${pathDigest}`,
    type: 'file-diff',
    url: referenceRawUrl,
  }
}

const generateFileReference = ({
  path,
  oid,
  repository,
}: {
  path?: string | null
  oid?: string
  repository: CopilotChatDiffEntry['repository']
}): FileReference | null => {
  if (!path || !oid) return null

  return {
    type: 'file' as const,
    url: repositoryTreePath({repo: repository, commitish: oid, action: 'raw', path}),
    path,
    repoID: repository.id,
    repoName: repository.name,
    repoOwner: repository.ownerLogin,
    ref: oid,
    commitOID: oid,
  }
}
