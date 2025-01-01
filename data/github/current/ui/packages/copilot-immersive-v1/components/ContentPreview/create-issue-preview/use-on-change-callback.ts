import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {useSessionStorage} from '@github-ui/use-safe-storage/session-storage'
import isEqual from 'lodash-es/isEqual'
import {useCallback} from 'react'

import type {DraftIssue} from '../content-preview-types'
import {useContentPreview} from '../ContentPreviewContext'
import {useUserEditedNewIssueId} from './use-user-edited-new-issue-id'

export function useOnChangeCallback(draftIssue: DraftIssue) {
  const {openItem, updateItem} = useContentPreview()
  const {selectedThreadID} = useChatState()
  const userEditedNewIssueId = useUserEditedNewIssueId(draftIssue.tag)
  const storageKey = `edited-${selectedThreadID}-${userEditedNewIssueId}`
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const [_, writeEditedIssueToStorage] = useSessionStorage<DraftIssue | undefined>(storageKey, undefined)

  return useCallback(
    (editedIssue: Partial<DraftIssue>, skipVersionBump: boolean = false) => {
      let hasChanges = false
      let property: keyof typeof editedIssue
      for (property in editedIssue) {
        if (!isEqual(editedIssue[property], draftIssue[property])) {
          hasChanges = true
          break
        }
      }

      if (!hasChanges) {
        return
      }

      const updatedItem: DraftIssue = {
        ...draftIssue,
        ...editedIssue,
      }

      if (!skipVersionBump) {
        updatedItem.id = userEditedNewIssueId
        updatedItem.isUserEdited = true
        if (copilotFeatureFlags.copilotPersistEditedDraftIssues) {
          writeEditedIssueToStorage(updatedItem)
        }
      }

      updateItem(updatedItem)
      openItem(updatedItem.id)
    },
    [draftIssue, userEditedNewIssueId, openItem, updateItem, writeEditedIssueToStorage],
  )
}
