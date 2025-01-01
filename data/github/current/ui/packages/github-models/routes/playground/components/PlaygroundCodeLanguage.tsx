import {ActionList, ActionMenu} from '@primer/react'
import {Stack} from '@primer/react/experimental'
import type {GettingStarted} from '../../../types'
import {testIdProps} from '@github-ui/test-id-props'

export function PlaygroundCodeLanguage({
  gettingStarted,
  preferredLanguage,
  handleSelectLanguage,
}: {
  gettingStarted: GettingStarted
  preferredLanguage: string
  handleSelectLanguage: (language: string) => void
}) {
  const languages = Object.keys(gettingStarted)
  const snippet = gettingStarted[preferredLanguage]

  if (!snippet) {
    return null
  }

  return (
    <Stack gap="normal" className="width-fit d-block">
      <ActionMenu>
        <ActionMenu.Button size="small" {...testIdProps('playground-language-button')}>
          {snippet.name}
        </ActionMenu.Button>
        <ActionMenu.Overlay width="small">
          <ActionList selectionVariant="single">
            {/* For each language, add an item to the dropdown */}
            {languages.map(language => (
              <ActionList.Item
                key={language}
                selected={language === preferredLanguage}
                onSelect={() => {
                  handleSelectLanguage(language)
                }}
              >
                {gettingStarted[language]?.name}
              </ActionList.Item>
            ))}
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </Stack>
  )
}
