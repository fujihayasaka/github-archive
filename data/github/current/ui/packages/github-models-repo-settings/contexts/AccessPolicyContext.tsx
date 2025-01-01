import type {UseMutateFunction} from '@github-ui/react-query'
import {createContext, type PropsWithChildren, useContext, useEffect, useMemo, useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {
  RepositoryAccessPolicy,
  RepositoryAccessPolicyShowPayload,
  UpdateRepositoryAccessPolicyPayload,
} from '../types'
import {useUpdateRepoAccessPolicy} from '../hooks/use-update-repository-access-policy'

interface AccessPolicyContextType extends RepositoryAccessPolicy {
  updateRepositoryAccessPolicy: UseMutateFunction<RepositoryAccessPolicy, Error, UpdateRepositoryAccessPolicyPayload>
  isUpdatePending: boolean
  didUpdateError: boolean
  isRepoModelsEnabled: boolean
}

const AccessPolicyContext = createContext<AccessPolicyContextType | undefined>(undefined)

export function useAccessPolicy() {
  const context = useContext(AccessPolicyContext)
  if (!context) throw new Error('useRepositoryAccessPolicy must be used within a RepositoryAccessPolicyProvider')
  return context
}

export function AccessPolicyProvider({children}: PropsWithChildren) {
  const {ownerDisplayLogin, repositoryName, repositoryAccessPolicy} =
    useRoutePayload<RepositoryAccessPolicyShowPayload>()
  const [policy, setPolicy] = useState(repositoryAccessPolicy)
  const {
    data: updatedPolicy,
    mutate: updateRepositoryAccessPolicy,
    isPending: isUpdatePending,
    isError: didUpdateError,
  } = useUpdateRepoAccessPolicy(ownerDisplayLogin, repositoryName)
  const {isRepoModelsEnabled} = policy
  const value = useMemo(
    () =>
      ({
        updateRepositoryAccessPolicy,
        isRepoModelsEnabled,
        didUpdateError,
        isUpdatePending,
      }) satisfies AccessPolicyContextType,
    [didUpdateError, isRepoModelsEnabled, isUpdatePending, updateRepositoryAccessPolicy],
  )

  useEffect(() => {
    if (updatedPolicy) setPolicy(updatedPolicy)
  }, [updatedPolicy, updatedPolicy?.isRepoModelsEnabled])

  return <AccessPolicyContext.Provider value={value}>{children}</AccessPolicyContext.Provider>
}
