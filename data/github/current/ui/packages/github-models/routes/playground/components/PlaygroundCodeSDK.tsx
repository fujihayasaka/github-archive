import {KebabHorizontalIcon} from '@primer/octicons-react'
import {ActionList, ActionMenu, IconButton, useResponsiveValue} from '@primer/react'
import {Stack} from '@primer/react/experimental'
import type {GettingStarted} from '../../../types'
import {testIdProps} from '@github-ui/test-id-props'
import type {ModelPersistentUIState} from '../../../utils/playground-local-storage'

export function PlaygroundCodeSDK({
  gettingStarted,
  uiState,
  handleSelectSDK,
}: {
  gettingStarted: GettingStarted
  uiState: ModelPersistentUIState
  handleSelectSDK: (sdk: string) => void
}) {
  const isMobile = useResponsiveValue({narrow: true}, false)
  const {preferredLanguage: selectedLanguage, preferredSdk: selectedSDK} = uiState
  const snippet = gettingStarted[selectedLanguage]

  if (!snippet) return null

  const sdks = Object.keys(snippet.sdks)

  if (!sdks.length) return null

  const sdkEntry = snippet.sdks[selectedSDK]

  if (!sdkEntry) return null

  return (
    <Stack gap="normal" className="width-fit d-block">
      <ActionMenu>
        {isMobile ? (
          <ActionMenu.Anchor>
            <IconButton
              icon={KebabHorizontalIcon}
              size="small"
              aria-label="Open SDK options"
              className="color-fg-muted"
            />
          </ActionMenu.Anchor>
        ) : (
          <ActionMenu.Button size="small" {...testIdProps('playground-sdk-button')}>
            {sdkEntry.name}
          </ActionMenu.Button>
        )}
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single">
            {sdks.map(sdk => (
              <ActionList.Item
                key={sdk}
                selected={sdk === selectedSDK}
                onSelect={() => {
                  handleSelectSDK(sdk)
                }}
              >
                {snippet.sdks[sdk]?.name}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </Stack>
  )
}
