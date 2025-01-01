import type {UseMutateFunction} from '@github-ui/react-query'
import {createContext, type PropsWithChildren, useContext, useEffect, useMemo, useState} from 'react'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {AccessPolicyShowPayload, OrganizationAccessPolicy, UpdateOrganizationAccessPolicyPayload} from '../types'
import {useUpdateOrganizationAccessPolicy} from '../hooks/use-update-organization-access-policy'

interface OrganizationAccessPolicyContextType extends Omit<OrganizationAccessPolicy, 'allowedModelKeys'> {
  updateOrganizationAccessPolicy: UseMutateFunction<
    OrganizationAccessPolicy,
    Error,
    UpdateOrganizationAccessPolicyPayload
  >
  isUpdatePending: boolean
  didUpdateError: boolean
  allowedModelKeys: Set<string>
}

const OrganizationAccessPolicyContext = createContext<OrganizationAccessPolicyContextType | undefined>(undefined)

export function useOrganizationAccessPolicy() {
  const context = useContext(OrganizationAccessPolicyContext)
  if (!context) throw new Error('useOrganizationAccessPolicy must be used within a OrganizationAccessPolicyProvider')
  return context
}

export function OrganizationAccessPolicyProvider({children}: PropsWithChildren) {
  const {orgDisplayLogin, ...payload} = useRoutePayload<AccessPolicyShowPayload>()
  const [policy, setPolicy] = useState(payload.policy)
  const {
    data: updatedPolicy,
    mutate: updateOrganizationAccessPolicy,
    isPending: isUpdatePending,
    isError: didUpdateError,
  } = useUpdateOrganizationAccessPolicy(orgDisplayLogin)
  const {isAllowlist, isModelsEnabled, allowedModelKeys} = policy
  const value = useMemo(
    () =>
      ({
        isAllowlist,
        isModelsEnabled,
        allowedModelKeys: new Set(allowedModelKeys),
        updateOrganizationAccessPolicy,
        didUpdateError,
        isUpdatePending,
      }) satisfies OrganizationAccessPolicyContextType,
    [allowedModelKeys, didUpdateError, isAllowlist, isModelsEnabled, isUpdatePending, updateOrganizationAccessPolicy],
  )

  useEffect(() => {
    if (updatedPolicy) setPolicy(updatedPolicy)
  }, [updatedPolicy, updatedPolicy?.isAllowlist, updatedPolicy?.isModelsEnabled, updatedPolicy?.allowedModelKeys])

  return <OrganizationAccessPolicyContext.Provider value={value}>{children}</OrganizationAccessPolicyContext.Provider>
}
