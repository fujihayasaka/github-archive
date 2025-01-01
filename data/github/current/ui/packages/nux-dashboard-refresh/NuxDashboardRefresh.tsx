import {Stack} from '@primer/react'
import BeginnersPlaylist from './components/BeginnerPlaylist/BeginnersPlaylist'
import {
  NewUserGettingStartedChecklist,
  type GettingStartedChecklist,
} from './components/NewUserGettingStartedChecklist/NewUserGettingStartedChecklist'
import {NuxDashboardDocs} from './components/NuxDashboardDocs/NuxDashboardDocs'
import {Recommendations} from './components/Recommendations/Recommendations'

export interface NuxDashboardRefreshProps {
  new_user_getting_started_checklist: GettingStartedChecklist
  dismissals: Dismissals
}

interface Dismissals {
  playlist_dismissed: boolean
  getting_started_dismissed: boolean
  docs_dismissed: boolean
  recommendations_dismissed: boolean
  vscode_dismissed: boolean
  desktop_dismissed: boolean
}

export function NuxDashboardRefresh({new_user_getting_started_checklist, dismissals}: NuxDashboardRefreshProps) {
  return (
    <Stack direction="vertical" gap="normal" className="mb-3">
      <BeginnersPlaylist dismissed={dismissals.playlist_dismissed} />
      <NewUserGettingStartedChecklist
        checklist={new_user_getting_started_checklist}
        dismissed={dismissals.getting_started_dismissed}
      />
      <NuxDashboardDocs heading="Start with GitHub Docs" dismissed={dismissals.docs_dismissed} />
      <Recommendations
        dismissed={dismissals.recommendations_dismissed}
        recommendationDismissals={{
          vscodeDismissed: dismissals.vscode_dismissed,
          desktopDismissed: dismissals.desktop_dismissed,
        }}
      />
    </Stack>
  )
}
