// TODO: Consolidate this and use-insights-actors into repos-shared package
import memoize from '@github/memoize'
import {useEffect, useState} from 'react'

import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import type {User, UsersState} from '@github-ui/user-selector'
import {bypassRequestersActorsPath, bypassApproversActorsPath} from '@github-ui/paths'
import type {FilterableUser} from '../delegated-bypass-types'
import {componentRegistry} from '../components/RequestForm/index'
import {useRequestTypeContext} from '../contexts/RequestTypeContext'

interface ActorsResponse {
  actors: User[]
}

async function fetchJSON(url: string): Promise<ActorsResponse | undefined> {
  const response = await verifiedFetchJSON(url)
  if (response.ok) {
    return await response.json()
  } else {
    return undefined
  }
}

const memoizeCache = new Map()
const memoizeFetchJSON = memoize(fetchJSON, {cache: memoizeCache})

/**
 * Retrieve a list of actors for a given repository
 *
 * returns an array of users, loading state and error
 * if cannot retrieve users, returns empty array
 */
export function useBypassActors(typeOfActor: FilterableUser): UsersState {
  const requestType = useRequestTypeContext()
  const {orgApproversUrl, orgRequestersUrl} = componentRegistry({requestType})

  let actorsPath = orgRequestersUrl || bypassRequestersActorsPath()
  if (typeOfActor === 'Approver') {
    actorsPath = orgApproversUrl || bypassApproversActorsPath()
  }

  const [usersState, setUsersState] = useState<UsersState>({
    users: [],
    error: false,
    loading: true,
  })

  useEffect(() => {
    let cancelled = false
    const update = async () => {
      setUsersState({
        users: [],
        error: false,
        loading: true,
      })

      const actorsResponse = await memoizeFetchJSON(actorsPath)

      if (cancelled) {
        return
      }

      let users: User[] = []
      let error = false

      try {
        if (actorsResponse) {
          users = actorsResponse.actors
        } else {
          error = true
        }
      } catch {
        error = true
      }

      setUsersState({
        users,
        error,
        loading: false,
      })
    }

    update()

    return function cancel() {
      cancelled = true
    }
  }, [actorsPath])

  return usersState
}
