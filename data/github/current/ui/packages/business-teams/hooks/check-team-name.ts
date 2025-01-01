import {debounce} from '@github/mini-throttle'
import {businessTeamCheckNamePath} from '@github-ui/paths'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useCallback, useState} from 'react'

export interface CheckResult {
  status: 'ok' | 'error' | 'not_found' | 'none' | 'unchanged'
  team?: string
  error?: string
}
interface BusinessTeamName {
  businessSlug: string
  name: string
  teamSlug?: string
}

/**
 * This hook returns 2 pieces:
 * 1. The result of the check ('none' if not run yet)
 * 2. A function to run the check on demand (and debounced)
 */
type ReturnType = [CheckResult, (newName: BusinessTeamName) => void]

/** A hook to check whether the business team name is valid when it changes */
export function useCheckBusinessTeamsName(onValidityChange: (isValid: boolean) => void): ReturnType {
  const [result, setResult] = useState<CheckResult>({status: 'none'})

  async function fetchCheck({name, businessSlug, teamSlug}: BusinessTeamName) {
    let url = businessTeamCheckNamePath({businessSlug})
    const searchParams = new URLSearchParams()
    searchParams.set('teamName', name)
    searchParams.set('teamOldSlug', teamSlug ?? '')
    url += `?${searchParams.toString()}`

    try {
      const response = await verifiedFetchJSON(url)
      const {team, error, message} = await response.json()
      if (response.status === 404) {
        setResult({status: 'not_found'})
      } else if (!response.ok) {
        setResult({status: 'error', team, error})
      } else {
        if (message === 'unchanged') {
          setResult({status: 'unchanged'})
          onValidityChange(true)
          return
        }
        setResult({status: 'ok', team})
        onValidityChange(true)
        return
      }
    } catch {
      setResult({status: 'error'})
    }

    onValidityChange(false)
  }
  // eslint-disable-next-line react-compiler/react-compiler
  // eslint-disable-next-line react-hooks/exhaustive-deps -- this lint rule wants an inline function, but debounce seems more natural
  const debouncedFetchCheck = useCallback(debounce(fetchCheck, 300), [])

  const runCheck = useCallback(
    (newName: BusinessTeamName) => {
      setResult({status: 'none'})
      if (newName.name && newName.businessSlug) {
        debouncedFetchCheck(newName)
      }
    },
    [debouncedFetchCheck],
  )

  return [result, runCheck]
}

export function isError(result: CheckResult): boolean {
  return result.status === 'error' || result.status === 'not_found'
}
