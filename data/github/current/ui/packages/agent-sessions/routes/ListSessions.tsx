import {Link} from '@github-ui/react-core/link'
import {listSessionsRoute} from './list-sessions'
import {showSessionRoute} from './show-session'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'

export function ListSessions() {
  const payload = useRouteQuery(listSessionsRoute, 'mainQuery')
  return (
    <>
      <h1 data-hpc>ListSessions for agent-sessions</h1>
      <ul>
        {payload.data.sessions.map(session => (
          <li key={session.id}>
            <Link
              to={showSessionRoute.generatePath({
                owner: payload.data.repository.ownerLogin,
                repo: payload.data.repository.name,
                session_id: session.id,
              })}
            >
              Session {session.id}
            </Link>
          </li>
        ))}
      </ul>
    </>
  )
}
