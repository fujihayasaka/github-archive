import {ActionList} from '@primer/react'
import {
  diffViewSettingsKey,
  updateQueryParam,
  useDiffViewSettingsData,
  type DiffViewSettings,
} from '../page-data/payloads/diff-view-settings'
import {useUpdateUserDiffViewPreferenceMutation} from '../hooks/mutations/use-update-user-diff-view-preference-mutation'
import {useQueryClient} from '@github-ui/react-query'
import {useCallback} from 'react'

export function DiffLinePresentationToggles({
  lineSpacingPreferenceAvailable = true,
  reloadOnChange = false,
}: {
  lineSpacingPreferenceAvailable?: boolean
  reloadOnChange?: boolean
}) {
  const {data} = useDiffViewSettingsData()
  const {mutate: updateUserDiffViewPreference} = useUpdateUserDiffViewPreferenceMutation({
    onSuccess: () => {},
    onError: () => {},
  })
  const queryClient = useQueryClient()

  const updateWhitespacePreference = useCallback(() => {
    if (!data) return
    queryClient.setQueryData(diffViewSettingsKey(), (old: DiffViewSettings) => {
      return {...old, hideWhitespace: !data.hideWhitespace}
    })
    updateQueryParam('w', !data.hideWhitespace ? '1' : '0')
    if (reloadOnChange) window.location.reload()
  }, [data, queryClient, reloadOnChange])

  if (!data) return null
  return (
    <ActionList.Group aria-label="Format" selectionVariant="multiple" variant="subtle">
      <ActionList.Item selected={data.hideWhitespace} onSelect={updateWhitespacePreference}>
        Hide whitespace
      </ActionList.Item>
      {lineSpacingPreferenceAvailable && (
        <ActionList.Item
          selected={data.lineSpacing === 'compact'}
          onSelect={() =>
            updateUserDiffViewPreference({lineSpacing: data.lineSpacing === 'compact' ? 'relaxed' : 'compact'})
          }
        >
          Compact line height
        </ActionList.Item>
      )}
    </ActionList.Group>
  )
}
