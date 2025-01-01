import {useMemo} from 'react'
import {
  generateCopilotChatReference,
  isValidForCopilotChat,
  type CopilotChatDiffEntry,
} from '../helpers/copilot-chat-helper'

type UseCopilotChatReferenceProps = CopilotChatDiffEntry & {
  hasCopilotAccess: boolean
}

export function useCopilotChatReference({
  isBinary,
  isSubmodule,
  path,
  status,
  repository,
  newCommitOid,
  newTreeEntry,
  oldCommitOid,
  oldTreeEntry,
  pathDigest,
  hasCopilotAccess,
}: UseCopilotChatReferenceProps) {
  return useMemo(() => {
    if (
      !isValidForCopilotChat({
        isBinary,
        isSubmodule,
        path,
        status,
        repository,
        hasCopilotAccess,
      })
    ) {
      return undefined
    }

    return generateCopilotChatReference({
      newCommitOid,
      newTreeEntry,
      oldCommitOid,
      oldTreeEntry,
      path,
      pathDigest,
      repository,
    })
  }, [
    newCommitOid,
    newTreeEntry,
    oldCommitOid,
    oldTreeEntry,
    pathDigest,
    repository,
    hasCopilotAccess,
    isBinary,
    isSubmodule,
    path,
    status,
  ])
}
