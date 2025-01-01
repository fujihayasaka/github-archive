import {ActionList} from '@primer/react'

import {CommentsPreference} from '../types'
import {useUpdateUserDiffViewPreferenceMutation} from '../hooks/mutations/use-update-user-diff-view-preference-mutation'
import {useDiffViewSettingsData} from '../page-data/payloads/diff-view-settings'

export function DiffCommentsPreferenceToggle() {
  const {data} = useDiffViewSettingsData()
  const {mutate: updateUserDiffViewPreference} = useUpdateUserDiffViewPreferenceMutation({
    onSuccess: () => {},
    onError: () => {},
  })

  if (!data) return null

  const isCollapsed = data.commentsPreference === CommentsPreference.Collapsed

  return (
    <>
      <ActionList.Divider />
      <ActionList.Group aria-label="Comments" selectionVariant="single">
        <ActionList.Item
          role="menuitemcheckbox"
          selected={isCollapsed}
          onSelect={() =>
            updateUserDiffViewPreference({
              commentsPreference: isCollapsed ? CommentsPreference.Visible : CommentsPreference.Collapsed,
            })
          }
        >
          Minimize comments
        </ActionList.Item>
      </ActionList.Group>
    </>
  )
}
