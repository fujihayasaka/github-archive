import type {CheckRun} from '@github-ui/commit-checks-status'
import {ProgressCircle} from '@github-ui/progress-circle'
import {commitStatusDetailsPath} from '@github-ui/paths'
import {useQuery} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {CheckCircleFillIcon, QuestionIcon, XCircleFillIcon} from '@primer/octicons-react'
import styles from '../DashboardLists.module.css'
import type {DashboardPullRequest} from '../types'

interface CheckRunCounts {
  total: number
  successful: number
}

function checkRunCounts(checkRuns: CheckRun[]): CheckRunCounts {
  return {
    total: checkRuns.length,
    successful: checkRuns.filter(checkRun => checkRun.state === 'success').length,
  }
}

export function StatusChecksRollup({pullRequest}: {pullRequest: DashboardPullRequest}) {
  const repo = pullRequest.repoNameWithOwner
  const oid = pullRequest.headSha
  const {
    isPending,
    isError,
    data: combinedStatusResult,
  } = useQuery({
    queryKey: [repo, oid],
    queryFn: async () => {
      const url = commitStatusDetailsPath(repo, oid)
      const response = await verifiedFetchJSON(url)
      return response.json()
    },
  })

  if (isPending || isError) {
    return null
  }

  if (combinedStatusResult) {
    const state = combinedStatusResult.checksHeaderState
    const counts = checkRunCounts(combinedStatusResult.checkRuns)
    const totalChecks = counts.total

    if (totalChecks === 0) {
      return null
    }

    if (state === 'PENDING') {
      const successfulChecks = counts.successful
      const percentCompleted = (successfulChecks / totalChecks) * 100
      return (
        <>
          <ProgressCircle percentCompleted={percentCompleted} size={16} />
          <span>{`${successfulChecks}/${totalChecks}`}</span>
        </>
      )
    } else if (state === 'SUCCEEDED') {
      return <CheckCircleFillIcon className={styles.SuccessIcon} />
    } else if (state === 'UNSUCCESSFUL' || state === 'FAILED') {
      return <XCircleFillIcon className={styles.FailureIcon} />
    } else {
      return <QuestionIcon />
    }
  }
}
