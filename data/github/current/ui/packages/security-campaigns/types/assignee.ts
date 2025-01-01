import type {User} from './user'

export type Assignee = User & {
  profilePath: string
  isCopilot: boolean
}
