import {useDiffViewSettings} from '../contexts/DiffViewSettingsContext'
import {ActionList} from '@primer/react'

export function DiffLinePresentationToggles({
  lineSpacingPreferenceAvailable = true,
  reloadOnChange = false,
}: {
  lineSpacingPreferenceAvailable?: boolean
  reloadOnChange?: boolean
}) {
  const {hideWhitespace, updateHideWhitespace, lineSpacing, updateLineSpacing} = useDiffViewSettings()

  return (
    <ActionList.Group selectionVariant="multiple" variant="subtle">
      <ActionList.Item
        selected={hideWhitespace}
        onSelect={() => {
          updateHideWhitespace(!hideWhitespace)
          if (reloadOnChange) window.location.reload()
        }}
      >
        Hide whitespace
      </ActionList.Item>
      {lineSpacingPreferenceAvailable && (
        <ActionList.Item
          selected={lineSpacing === 'compact'}
          onSelect={() => updateLineSpacing(lineSpacing === 'compact' ? 'relaxed' : 'compact')}
        >
          Compact line height
        </ActionList.Item>
      )}
    </ActionList.Group>
  )
}
