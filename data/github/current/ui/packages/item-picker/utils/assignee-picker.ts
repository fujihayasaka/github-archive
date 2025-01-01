import type {RepositorySuggestedActorFilter} from '../components/__generated__/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import type {Assignee} from '../components/AssigneePicker'

type GetActorCapabilitiesParams = {
  includeAssignableBots?: boolean
  includeAuthorableBots?: boolean
}

export const getActorCapabilities = ({
  includeAssignableBots,
  includeAuthorableBots,
}: GetActorCapabilitiesParams): RepositorySuggestedActorFilter[] => {
  const capabilities: RepositorySuggestedActorFilter[] = []

  if (includeAssignableBots) {
    capabilities.push('CAN_BE_ASSIGNED')
  }
  if (includeAuthorableBots) {
    capabilities.push('CAN_BE_AUTHOR')
  }

  return capabilities
}

export const formatActorLogin = (actor: Assignee) => {
  if (actor.isCopilot) return '@copilot'

  if (actor.__typename === 'Bot') {
    return `app/${actor.login}`
  }

  return actor.login
}
