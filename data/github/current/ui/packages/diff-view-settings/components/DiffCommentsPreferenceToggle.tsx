import {ActionList} from '@primer/react'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

import {CommentsPreference} from '../types'
import {useUpdateUserDiffViewPreferenceMutation} from '../hooks/mutations/use-update-user-diff-view-preference-mutation'
import {useDiffViewSettingsData} from '../page-data/payloads/diff-view-settings'

export function DiffCommentsPreferenceToggle() {
  const {diff_inline_comments: diffInlineCommentsFeatureIsEnabled} = useFeatureFlags()
  const {data} = useDiffViewSettingsData()
  const {mutate: updateUserDiffViewPreference} = useUpdateUserDiffViewPreferenceMutation({
    onSuccess: () => {},
    onError: () => {},
  })

  if (!data) return null
  if (!diffInlineCommentsFeatureIsEnabled) return null

  return (
    <ActionList.Group selectionVariant="single">
      <ActionList.GroupHeading>Comments</ActionList.GroupHeading>
      <ActionList.Item
        selected={data.commentsPreference === CommentsPreference.Collapsed}
        onSelect={() => updateUserDiffViewPreference({commentsPreference: CommentsPreference.Collapsed})}
      >
        Collapsed
      </ActionList.Item>
      <ActionList.Item
        selected={data.commentsPreference === CommentsPreference.Visible}
        onSelect={() => updateUserDiffViewPreference({commentsPreference: CommentsPreference.Visible})}
      >
        Expanded
      </ActionList.Item>
    </ActionList.Group>
  )
}
