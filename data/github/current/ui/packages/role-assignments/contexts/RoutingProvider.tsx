import {createContext, useContext, useMemo} from 'react'
import {
  enterpriseRoleAssignmentsPath,
  newEnterpriseRoleAssignmentPath,
  enterpriseRolesPath,
  orgRoleAssignmentsPath,
  newOrgRoleAssignmentPath,
  stafftoolsEnterpriseRoleAssignmentsPath,
  stafftoolsOrgRoleAssignmentsPath,
  destroyEnterpriseRoleAssignmentPath,
  destroyOrgRoleAssignmentPath,
} from '@github-ui/paths'
import type {ActorType} from '../types/ActorRoleAssignment'

type OwnerType = 'enterprise' | 'organization'

interface RoutingContextProps {
  slug: string
  roleAssignmentsPath: (params: {page?: number; query?: string}) => string
  newRoleAssignmentPath: () => string
  rolesPath: () => string
  destroyRoleAssignmentPath: (params: {actorId: number; actorType: ActorType; roleId: number}) => string
}

interface RoutingProviderProps {
  children: React.ReactNode
  slug: string
  ownerType: OwnerType
  stafftools?: boolean
}

const RoutingContext = createContext<RoutingContextProps | undefined>(undefined)

const ownerTypeToPathMap = {
  enterprise: {
    roleAssignmentsPath: enterpriseRoleAssignmentsPath,
    newRoleAssignmentPath: newEnterpriseRoleAssignmentPath,
    rolesPath: enterpriseRolesPath,
    destroyRoleAssignmentPath: destroyEnterpriseRoleAssignmentPath,
  },
  organization: {
    roleAssignmentsPath: orgRoleAssignmentsPath,
    newRoleAssignmentPath: newOrgRoleAssignmentPath,
    rolesPath: () => '',
    destroyRoleAssignmentPath: destroyOrgRoleAssignmentPath,
  },
}

const ownerTypeToPathMapStafftools = {
  enterprise: {
    roleAssignmentsPath: stafftoolsEnterpriseRoleAssignmentsPath,
    newRoleAssignmentPath: () => '',
    rolesPath: () => '',
    destroyRoleAssignmentPath: () => '',
  },
  organization: {
    roleAssignmentsPath: stafftoolsOrgRoleAssignmentsPath,
    newRoleAssignmentPath: () => '',
    rolesPath: () => '',
    destroyRoleAssignmentPath: () => '',
  },
}

export const RoutingProvider = ({children, slug, ownerType, stafftools = false}: RoutingProviderProps) => {
  const value = useMemo(() => {
    const routesMapping = stafftools ? ownerTypeToPathMapStafftools : ownerTypeToPathMap

    const roleAssignmentsPath = (params: {page?: number; query?: string}) =>
      routesMapping[ownerType]?.roleAssignmentsPath({...params, slug})
    const newRoleAssignmentPath = () => routesMapping[ownerType]?.newRoleAssignmentPath({slug})
    const rolesPath = () => routesMapping[ownerType]?.rolesPath({slug})
    const destroyRoleAssignmentPath = (params: {actorId: number; actorType: string; roleId: number}) =>
      routesMapping[ownerType]?.destroyRoleAssignmentPath({...params, slug})

    return {
      slug,
      roleAssignmentsPath,
      newRoleAssignmentPath,
      rolesPath,
      destroyRoleAssignmentPath,
    }
  }, [slug, ownerType, stafftools])

  return <RoutingContext.Provider value={value}>{children}</RoutingContext.Provider>
}

export const useRoutingContext = () => {
  const context = useContext(RoutingContext)
  if (!context) {
    throw new Error('useRoutingContext must be used within a RoutingProvider')
  }
  return context
}
