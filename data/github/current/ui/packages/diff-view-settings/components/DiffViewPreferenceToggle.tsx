import {ActionList} from '@primer/react'
import {useUpdateUserDiffViewPreferenceMutation} from '../hooks/mutations/use-update-user-diff-view-preference-mutation'
import {updateQueryParam, useDiffViewSettingsData} from '../page-data/payloads/diff-view-settings'

export function DiffViewPreferenceToggle({reloadOnChange = false}: {reloadOnChange?: boolean}) {
  const {data} = useDiffViewSettingsData()
  const splitPreference = data?.splitPreference

  const {mutate: updateUserDiffViewPreference} = useUpdateUserDiffViewPreferenceMutation({
    onSuccess: () => {},
    onError: () => {},
  })

  return (
    <ActionList.Group selectionVariant="single">
      <ActionList.GroupHeading>Layout</ActionList.GroupHeading>
      <ActionList.Item
        selected={splitPreference === 'unified'}
        onSelect={() => {
          updateUserDiffViewPreference({splitPreference: 'unified'})
          updateQueryParam('diff', 'unified')
          if (reloadOnChange) window.location.reload()
        }}
      >
        Unified
      </ActionList.Item>
      <ActionList.Item
        selected={splitPreference === 'split'}
        onSelect={() => {
          updateUserDiffViewPreference({splitPreference: 'split'})
          updateQueryParam('diff', 'split')
          if (reloadOnChange) window.location.reload()
        }}
      >
        Split
      </ActionList.Item>
    </ActionList.Group>
  )
}
