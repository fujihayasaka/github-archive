import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {CurrentUserProvider} from '@github-ui/current-user'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type React from 'react'
import {useState} from 'react'

import {CommitErrorState} from './components/CommitErrorState'
import type {CommitsBasePayload} from './shared/types'

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  const payload = useRoutePayload<CommitsBasePayload>()
  const [repo] = useState(payload?.repo)
  const [user] = useState(payload?.currentUser)

  return (
    <ErrorBoundary critical fallback={<CommitErrorState />}>
      <CurrentUserProvider user={user}>
        <CurrentRepositoryProvider repository={repo}>{props.children}</CurrentRepositoryProvider>
      </CurrentUserProvider>
    </ErrorBoundary>
  )
}
