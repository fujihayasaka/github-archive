import type {Model} from '@github-ui/marketplace-common'
import type {PlaygroundMessage} from '../types'
import type {User} from '@github-ui/use-user'

export const determineMessageMeta = (message: PlaygroundMessage, model: Model, currentUser: User | null) => {
  switch (message.role) {
    case 'error':
    case 'assistant':
      return {
        name: model.friendly_name,
        avatarUrl: model.logo_url ?? '/github.png',
      }
    case 'user':
      return {
        name: currentUser?.name ?? 'User',
        avatarUrl: currentUser?.avatarUrl ?? '/github.png',
      }
    default:
      return {
        name: 'default',
        avatarUrl: '/github.png',
      }
  }
}
