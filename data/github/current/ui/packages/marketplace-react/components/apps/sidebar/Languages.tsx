import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {joinWords} from '../../../utilities/join-words'
import {Stack} from '@primer/react'

export type LanguagesProps = {
  supportedLanguages: string[]
}

export function Languages({supportedLanguages}: LanguagesProps) {
  return supportedLanguages.length ? (
    <Stack gap="condensed" data-testid="languages">
      <SidebarHeading title="Supported languages" htmlTag="h2" count={supportedLanguages?.length} />
      <span>{joinWords(supportedLanguages)}</span>
    </Stack>
  ) : null
}
