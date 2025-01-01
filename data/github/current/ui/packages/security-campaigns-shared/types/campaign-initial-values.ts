import type {Team} from './team'
import type {User} from './user'

export type CampaignInitialValues = {
  id?: number
  name: string | null
  description: string | null
  endsAt: string | null
  managers: User[]
  teamManagers: Team[]
  contactLink: string | null
}
