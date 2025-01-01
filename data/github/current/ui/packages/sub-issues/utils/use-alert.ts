import {useCallback, useState} from 'react'

// These values should be in sync with the server-side values found in packages/hierarchy/app/models/sub_issue.rb
const MAX_HEIGHT = 7

export function useAlert() {
  const [alert, setAlert] = useState<{title: string; body: string} | null>(null)

  const resetAlert = useCallback(() => setAlert(null), [])

  const showBreadthLimitAlert = useCallback(
    (limit: number) =>
      setAlert({
        title: 'Sub-issue limit reached',
        body: `Parents have a limit of ${limit} sub-issues. To add more, an existing one must be removed.`,
      }),

    [],
  )

  const showDepthLimitAlert = useCallback(
    () =>
      setAlert({
        title: 'Sub-issue limit reached',
        body: `You can’t add more than ${MAX_HEIGHT} layers of sub-issues. To add a sub-issue, remove a parent issue at any level.`,
      }),

    [],
  )

  const showCircularDependencyAlert = useCallback(
    () =>
      setAlert({
        title: 'Sub-issue circular dependency',
        body: `A parent may not be a sub-issue of itself. To add it as a sub-issue, remove it as a parent in the tree.`,
      }),

    [],
  )

  const showDuplicateSubIssueAlert = useCallback(() => {
    setAlert({
      title: 'Duplicate sub-issue',
      body: `A parent may not have duplicate sub-issues.`,
    })
  }, [])

  const showPermissionsAlert = useCallback(() => {
    setAlert({
      title: 'Access denied',
      body: `You do not have permission to take this action for the selected issue. A repository role of 'triage' or higher is required.`,
    })
  }, [])

  const showOwnerAlert = useCallback(() => {
    setAlert({
      title: 'Invalid owner',
      body: `A sub-issue must belong to the same organization or user as the parent.`,
    })
  }, [])

  const showServerAlert = useCallback(
    (error: Error) => {
      // We parse the limit here to be more resilient to changes in limit which is defined by the backend
      const limitMatch = error.message.match(/Parent cannot have more than (?<limit>\d+) sub-issues/)
      const limit = parseInt(limitMatch?.groups?.limit || 'NaN', 10)
      if (!isNaN(limit)) {
        showBreadthLimitAlert(limit)
        return true
      }

      if (error.message.includes(`You can’t add more than ${MAX_HEIGHT} layers of sub-issues`)) {
        showDepthLimitAlert()
        return true
      }

      if (error.message.includes('does not have the correct permissions to execute `AddSubIssue`')) {
        showPermissionsAlert()
        return true
      }

      if (
        error.message.includes('Sub issue may not create a circular dependency') ||
        error.message.includes('Sub issue cannot be the same as the parent issue')
      ) {
        showCircularDependencyAlert()
        return true
      }

      if (error.message.includes('Issue may not contain duplicate sub-issues')) {
        showDuplicateSubIssueAlert()
        return true
      }

      if (error.message.includes('Sub issue must have the same owner as the parent')) {
        showOwnerAlert()
        return true
      }

      return false
    },
    [
      showBreadthLimitAlert,
      showCircularDependencyAlert,
      showDepthLimitAlert,
      showDuplicateSubIssueAlert,
      showPermissionsAlert,
      showOwnerAlert,
    ],
  )

  return {alert, setAlert, resetAlert, showBreadthLimitAlert, showServerAlert}
}
