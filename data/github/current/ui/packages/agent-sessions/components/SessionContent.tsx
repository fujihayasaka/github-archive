import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {showSessionRoute} from '../routes/show-session'

import styles from './SessionContent.module.css'

export function SessionContent() {
  const payload = useRouteQuery(showSessionRoute, 'mainQuery')

  return (
    <div className={styles.sessionContent}>
      <h1>Session details</h1>
      <pre>{JSON.stringify(payload.data.session, null, 2)}</pre>
    </div>
  )
}
