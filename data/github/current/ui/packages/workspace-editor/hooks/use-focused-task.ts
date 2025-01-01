import {useMemo} from 'react'
import {useSearchParams} from 'react-router-dom'

import {focusedTaskQueryParam} from '../utilities/query-params'

export const useFocusedTask = () => {
  const [searchParams] = useSearchParams()
  const focusedTask = searchParams.get(focusedTaskQueryParam)
  const initialTaskType = searchParams.get('type')
  const taskId = useMemo(() => {
    const parsedTaskId = Number(focusedTask)
    return isNaN(parsedTaskId) ? null : parsedTaskId
  }, [focusedTask])

  return {
    initialTaskId: taskId,
    // Currently only supported type access needed for telemetry.
    // Fix if we add more in the future.
    initialTaskSource: 'pull_request_review_comment',
    initialTaskType,
  }
}
