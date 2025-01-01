import {debounce} from '@github/mini-throttle'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useCallback, useState} from 'react'

import type {WorkbenchRoutePayload} from '../types/workbench-types'

export interface CheckResult {
  status: 'ok' | 'reworded' | 'error' | 'not_found' | 'none'
  generatedName?: string
  errors?: string
}

export interface SparkName {
  friendlyName: string
}

/**
 * This hook returns 2 pieces:
 * 1. The result of the check ('none' if not run yet)
 * 2. A function to run the check on demand (and debounced)
 */
type ReturnType = [CheckResult, (newName: SparkName) => void]

/** A hook to check whether the friendly name is valid when it changes */
export function useCheckName(
  onValidityChange: ({valid, invalidReason}: {valid: boolean; invalidReason?: string}) => void,
): ReturnType {
  const {workbench} = useRoutePayload<WorkbenchRoutePayload>()
  const [result, setResult] = useState<CheckResult>({status: 'none'})

  async function fetchCheck({friendlyName: newFriendlyName}: SparkName) {
    let status: 'ok' | 'reworded' | 'error' | 'not_found' | 'none' = 'none'
    let invalidReason: string | undefined

    try {
      const response = await verifiedFetch(`/copilot/spark/runtime/names`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          desired_spark_friendly_name: newFriendlyName,
          permanent_name: workbench.runtimePermanentName,
        }),
      })

      const {generatedName, errors} = await response.json()
      if (response.status === 404) {
        status = 'not_found'
        setResult({status})
      } else if (!response.ok) {
        status = 'error'
        invalidReason = getErrorReason(errors)
        setResult({status, generatedName, errors})
      } else {
        setResult({status: generatedName === newFriendlyName ? 'ok' : 'reworded', generatedName})
        onValidityChange({valid: true})
        return
      }
    } catch {
      status = 'error'
      setResult({status})
    }

    onValidityChange({valid: false, invalidReason: invalidReason ?? status})
  }

  // eslint-disable-next-line react-hooks/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps -- this lint rule wants an inline function, but debounce seems more natural
  const debouncedFetchCheck = useCallback(debounce(fetchCheck, 300), [])

  const runCheck = useCallback(
    (newName: SparkName) => {
      setResult({status: 'none'})

      if (!newName.friendlyName) {
        onValidityChange({valid: false, invalidReason: 'empty'})
      }

      if (newName.friendlyName) {
        debouncedFetchCheck(newName)
      }
    },
    [debouncedFetchCheck, onValidityChange],
  )

  return [result, runCheck]
}

export function isError(result: CheckResult): boolean {
  return result?.status === 'error' || result?.status === 'not_found'
}

function getErrorReason(errors?: string): string {
  if (!errors) {
    return 'unknown_error'
  }

  if (errors.startsWith('is too long')) {
    return 'too_long'
  }

  if (errors.startsWith('already exists')) {
    return 'in_use'
  }

  // empty repo name is handled in component
  return 'unknown_error'
}
