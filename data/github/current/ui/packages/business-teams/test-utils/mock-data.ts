import type {BusinessTeamsListViewPayload} from '../routes/BusinessTeamsListView'

export function getBusinessTeamsTableViewRoutePayload(): BusinessTeamsListViewPayload {
  return {
    someField: 'Payload for the business-teams BusinessTeamsListView route',
  }
}
