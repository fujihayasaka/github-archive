import type {Session} from './session'
import type {Pull} from './pull'

export type SessionItem = {
  pull: Pull
  sessions: Session[]
}
