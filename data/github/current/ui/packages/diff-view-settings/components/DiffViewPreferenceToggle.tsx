import {useDiffViewSettings} from '../contexts/DiffViewSettingsContext'
import {ActionList} from '@primer/react'

export function DiffViewPreferenceToggle({reloadOnChange = false}: {reloadOnChange?: boolean}) {
  const {splitPreference, updateSplitPreference} = useDiffViewSettings()

  return (
    <ActionList.Group selectionVariant="single">
      <ActionList.GroupHeading>Layout</ActionList.GroupHeading>
      <ActionList.Item
        selected={splitPreference === 'unified'}
        onSelect={() => {
          updateSplitPreference('unified')
          if (reloadOnChange) window.location.reload()
        }}
      >
        Unified
      </ActionList.Item>
      <ActionList.Item
        selected={splitPreference === 'split'}
        onSelect={() => {
          updateSplitPreference('split')
          if (reloadOnChange) window.location.reload()
        }}
      >
        Split
      </ActionList.Item>
    </ActionList.Group>
  )
}
