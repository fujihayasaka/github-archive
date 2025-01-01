import type {UseMutateFunction} from '@github-ui/react-query'
import {createContext, type PropsWithChildren, useCallback, useContext, useMemo, useState} from 'react'
import type {
  OrganizationAccessPolicy,
  UpdateOrganizationAccessPolicyPayload,
  OrganizationAccessPolicyUpdateType,
} from '../types'
import {useUpdateOrganizationAccessPolicy} from '../hooks/use-update-organization-access-policy'

interface OrganizationAccessPolicyContextType
  extends Omit<OrganizationAccessPolicy, 'allowedModelKeys' | 'allowedCustomModelIds'> {
  updateOrganizationAccessPolicy: UseMutateFunction<
    OrganizationAccessPolicy,
    Error,
    UpdateOrganizationAccessPolicyPayload
  >
  isUpdatePending: boolean
  pendingUpdateType: OrganizationAccessPolicyUpdateType | null
  didUpdateError: boolean
  allowedModelKeys: Set<string>
}

const OrganizationAccessPolicyContext = createContext<OrganizationAccessPolicyContextType | undefined>(undefined)

export function useOrganizationAccessPolicy() {
  const context = useContext(OrganizationAccessPolicyContext)
  if (!context) throw new Error('useOrganizationAccessPolicy must be used within a OrganizationAccessPolicyProvider')
  return context
}

export function OrganizationAccessPolicyProvider({
  children,
  policy,
  orgDisplayLogin,
}: PropsWithChildren<{
  policy: OrganizationAccessPolicy
  orgDisplayLogin: string
}>) {
  const [pendingUpdateType, setPendingUpdateType] = useState<OrganizationAccessPolicyUpdateType | null>(null)
  const {
    data: updatedPolicy,
    mutate: updateOrganizationAccessPolicyMutate,
    isPending: isUpdatePending,
    isError: didUpdateError,
  } = useUpdateOrganizationAccessPolicy({orgDisplayLogin, setPendingUpdateType})

  // TODO: Once we land DataRouter, Policy will be updated from the mutation and wont require reading updatedPolicy here
  const {isAllowlist, isModelsEnabled, isAccessConfigurable, allowedModelKeys} = updatedPolicy ?? policy

  const updateOrganizationAccessPolicy = useCallback(
    (...args: Parameters<typeof updateOrganizationAccessPolicyMutate>) => {
      if (!isAccessConfigurable) return
      return updateOrganizationAccessPolicyMutate(...args)
    },
    [updateOrganizationAccessPolicyMutate, isAccessConfigurable],
  )

  const value = useMemo(
    () =>
      ({
        isAllowlist,
        isModelsEnabled,
        isAccessConfigurable,
        allowedModelKeys: new Set(allowedModelKeys),
        updateOrganizationAccessPolicy,
        didUpdateError,
        isUpdatePending,
        pendingUpdateType,
      }) satisfies OrganizationAccessPolicyContextType,
    [
      allowedModelKeys,
      didUpdateError,
      isAllowlist,
      isModelsEnabled,
      isAccessConfigurable,
      isUpdatePending,
      pendingUpdateType,
      updateOrganizationAccessPolicy,
    ],
  )

  return <OrganizationAccessPolicyContext.Provider value={value}>{children}</OrganizationAccessPolicyContext.Provider>
}
