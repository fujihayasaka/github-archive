import type {User} from '@github-ui/use-user'
import type {RepoModel} from '../../../types'
import type {Message} from '../types'

export const determineMessageMeta = (message: Message, model: RepoModel, currentUser: User | null) => {
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
