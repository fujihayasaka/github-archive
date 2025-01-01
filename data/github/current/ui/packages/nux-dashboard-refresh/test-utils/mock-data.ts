import type {NuxDashboardRefreshProps} from '../NuxDashboardRefresh'

export function getNuxDashboardRefreshProps(): NuxDashboardRefreshProps {
  return {
    new_user_getting_started_checklist: {
      has_customized_account: false,
      has_tried_copilot: false,
      has_created_repo: false,
    },
    dismissals: {
      playlist_dismissed: false,
      getting_started_dismissed: false,
      docs_dismissed: false,
      recommendations_dismissed: false,
      vscode_dismissed: false,
      desktop_dismissed: false,
    },
  }
}

export function getNuxDashboardRefreshPropsForSSRTest(): NuxDashboardRefreshProps {
  return {
    new_user_getting_started_checklist: {
      has_customized_account: true,
      has_tried_copilot: false,
      has_created_repo: false,
    },
    dismissals: {
      playlist_dismissed: false,
      getting_started_dismissed: false,
      docs_dismissed: false,
      recommendations_dismissed: false,
      vscode_dismissed: false,
      desktop_dismissed: true,
    },
  }
}

export function getNuxDashboardRefreshPropsWithCompletedChecklist(): NuxDashboardRefreshProps {
  return {
    new_user_getting_started_checklist: {
      has_customized_account: true,
      has_tried_copilot: true,
      has_created_repo: true,
    },
    dismissals: {
      playlist_dismissed: false,
      getting_started_dismissed: false,
      docs_dismissed: false,
      recommendations_dismissed: false,
      vscode_dismissed: false,
      desktop_dismissed: false,
    },
  }
}
