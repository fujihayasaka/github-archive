import type {PickerRepository} from '@github-ui/repos-picker'
import type {EnterpriseTeamSeatAssignment, SeatType} from '../types'

export type CopilotStandaloneSeatManagementPayload = {
  business: {
    login: string
    slug: string
  }
  count: number
  filtered_count: number
  total_seats: number
  seatAssignments: EnterpriseTeamSeatAssignment[]
}

export type SelectionMode = 'no_repos' | 'all_repos' | 'multiple'
export type CopilotSweAgentPayload = {
  project_display_name: string
  selection: PickerRepository[]
  org_login: string
  mode: SelectionMode
  selections_changed_callback_path: string
  mode_changed_callback_path: string
  access_warning_banner_content?: string
}

export type EnterpriseTeamAssignable = {id: number; type: SeatType; name: string}
export type EnterpriseTeamAssignables = EnterpriseTeamAssignable[]
