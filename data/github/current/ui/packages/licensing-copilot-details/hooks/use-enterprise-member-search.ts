import {useCallback, useState, useEffect} from 'react'
import {verifiedFetch} from '@github-ui/verified-fetch'
import type {User} from '../types'

export function useEnterpriseMemberSearch(basePath: string, searchQuery: string) {
  const [users, setUsers] = useState<User[]>([])
  const [loading, setLoading] = useState<boolean>(false)
  const [isEmpty, setIsEmpty] = useState<boolean>(true)
  const [hasQuery, setHasQuery] = useState<boolean>(false)

  const searchUsers = useCallback(
    async (query: string): Promise<void> => {
      setHasQuery(!!query && query.length > 0)

      if (!query || query.length < 1) {
        setUsers([])
        setIsEmpty(true)
        setLoading(false)
        return
      }

      setLoading(true)
      setIsEmpty(false)

      try {
        const queryParams = query ? `?query=${encodeURIComponent(query)}` : ''
        const response = await verifiedFetch(`${basePath}/enterprise_licensing/user_licenses${queryParams}`, {
          method: 'GET',
          headers: {Accept: 'application/json'},
        })

        if (response.ok) {
          const data = await response.json()
          const results = data.withoutCopilotAccess || []
          setUsers(results || [])
          setIsEmpty((results || []).length === 0)
        } else {
          setUsers([])
          setIsEmpty(true)
        }
      } catch {
        setUsers([])
        setIsEmpty(true)
      } finally {
        setLoading(false)
      }
    },
    [basePath],
  )

  // Trigger search when searchQuery changes
  useEffect(() => {
    searchUsers(searchQuery)
  }, [searchQuery, searchUsers])

  return {users, loading, isEmpty, hasQuery}
}
