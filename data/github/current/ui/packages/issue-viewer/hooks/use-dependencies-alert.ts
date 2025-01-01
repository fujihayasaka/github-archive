import {useCallback, useState} from 'react'

export function useDependencyAlerts() {
  const [alerts, setAlerts] = useState<Array<{title: string; body: string}>>([])

  const resetAlerts = useCallback(() => setAlerts([]), [])

  const appendBreadthAlert = useCallback(
    (limit: number, relationship: string) => {
      let relationshipType = ''
      switch (relationship) {
        case 'blocked-by': {
          relationshipType = '"blocked by" '
          break
        }
        case 'blocking': {
          relationshipType = '"blocking" '
          break
        }
      }
      setAlerts(currentAlerts => [
        ...currentAlerts,
        {
          title: 'Dependency limit reached',
          body: `Issues have a limit of ${limit} ${relationshipType}relationships. To add more, an existing one must be removed.`,
        },
      ])
    },

    [],
  )

  const appendCircularDependencyAlert = useCallback(
    () =>
      setAlerts(currentAlerts => [
        ...currentAlerts,
        {
          title: 'Circular dependency',
          body: 'An issue may not be blocked by an issue that it is already blocking. Please remove the existing relationship before adding this one.',
        },
      ]),
    [],
  )

  const appendPermissionAlert = useCallback(
    () =>
      setAlerts(currentAlerts => [
        ...currentAlerts,
        {
          title: 'Access denied',
          body: `You do not have permission to take this action for the selected issue. A repository role of 'triage' or higher is required on the blocked issue.`,
        },
      ]),
    [],
  )

  const setAlertsFromErrors = useCallback(
    (errors: Error[]) => {
      for (const error of errors) {
        // We parse the limit here to be more resilient to changes in limit which is defined by the backend
        const limitMatch = error.message.match(
          /cannot have more than (?<limit>\d+) (?<relationship>blocked-by|blocking) relations/,
        )
        const limit = parseInt(limitMatch?.groups?.limit || 'NaN', 10)
        if (!isNaN(limit)) {
          appendBreadthAlert(limit, limitMatch?.groups?.relationship ?? 'blocked-by')
          continue
        }

        if (error.message.includes('does not have the correct permissions to execute')) {
          appendPermissionAlert()
          continue
        }

        if (
          error.message.includes(
            'this dependency would create a cycle where the target is already blocked by the source',
          )
        ) {
          appendCircularDependencyAlert()
          continue
        }

        setAlerts(currentAlerts => [
          ...currentAlerts,
          {
            title: 'Unexpected error',
            body: `An unexpected error occurred. ${error.message}`,
          },
        ])
      }
    },
    [appendBreadthAlert, appendCircularDependencyAlert, appendPermissionAlert],
  )

  return {alerts, setAlerts, resetAlerts, setAlertsFromErrors}
}
