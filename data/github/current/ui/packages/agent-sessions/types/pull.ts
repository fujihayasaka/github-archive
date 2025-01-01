export type Pull = {
  id: number
  number: number
  title: string
  state: 'open' | 'closed' | 'merged'
  reviewable_state: 'draft' | 'ready'
  url: string
  labels: string[]
  comments: number
  assignees_avatar_urls?: string[]
  created_at: string
  updated_at: string
  merged_at?: string
  closed_at?: string
  author: string
  head_sha: string
  repository_nwo: string
}
