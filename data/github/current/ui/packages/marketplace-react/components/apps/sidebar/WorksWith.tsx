import SidebarHeading from '@github-ui/marketplace-common/SidebarHeading'
import {Stack} from '@primer/react'

export type WorksWithProps = {
  isCopilotApp: boolean
}

export function WorksWith({isCopilotApp}: WorksWithProps) {
  return (
    isCopilotApp && (
      <Stack gap="condensed" data-testid="apps-works-with">
        <SidebarHeading title="Works with" htmlTag="h2" />
        <span>Copilot Chat, Copilot in the IDE</span>
      </Stack>
    )
  )
}
