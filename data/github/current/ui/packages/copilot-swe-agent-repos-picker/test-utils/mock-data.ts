import type {CopilotSweAgentReposPickerProps} from '../CopilotSweAgentReposPicker'

export function getCopilotSweAgentReposPickerProps(): CopilotSweAgentReposPickerProps {
  return {
    userLogin: 'monalisa',
    selection: [],
    mode: 'no_repos',
    projectDisplayName: 'Copilot coding agent',
    modeChangedCallbackPath: 'settings/copilot/swe_agent',
    selectionsChangedCallbackPath: 'settings/copilot/swe_agent',
  }
}
