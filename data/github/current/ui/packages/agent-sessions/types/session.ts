export type Session = {
  id: string
  user_id: number
  agent_id: number
  state: string
  owner_id: number
  repo_id: number
  resource_type: string
  resource_id: number
  created_at: Date
  last_updated_at: Date
  completed_at: Date | undefined
}
