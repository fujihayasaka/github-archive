import {createContext, useContext, useMemo} from 'react'
import {
  enterpriseRoleAssignmentsPath,
  newEnterpriseRoleAssignmentPath,
  enterpriseRolesPath,
  orgRoleAssignmentsPath,
  newOrgRoleAssignmentPath,
  stafftoolsEnterpriseRoleAssignmentsPath,
} from '@github-ui/paths'

type OwnerType = 'enterprise' | 'organization'

interface RoutingContextProps {
  slug: string
  roleAssignmentsPath: (params: {page?: number; query?: string}) => string
  newRoleAssignmentPath: () => string
  rolesPath: () => string
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
  },
  organization: {
    roleAssignmentsPath: orgRoleAssignmentsPath,
    newRoleAssignmentPath: newOrgRoleAssignmentPath,
    rolesPath: () => '',
  },
}

const ownerTypeToPathMapStafftools = {
  enterprise: {
    roleAssignmentsPath: stafftoolsEnterpriseRoleAssignmentsPath,
    newRoleAssignmentPath: () => '',
    rolesPath: () => '',
  },
  organization: {
    roleAssignmentsPath: () => '',
    newRoleAssignmentPath: () => '',
    rolesPath: () => '',
  },
}

export const RoutingProvider = ({children, slug, ownerType, stafftools = false}: RoutingProviderProps) => {
  const value = useMemo(() => {
    const routesMapping = stafftools ? ownerTypeToPathMapStafftools : ownerTypeToPathMap

    const roleAssignmentsPath = (params: {page?: number; query?: string}) =>
      routesMapping[ownerType]?.roleAssignmentsPath({...params, slug})
    const newRoleAssignmentPath = () => routesMapping[ownerType]?.newRoleAssignmentPath({slug})
    const rolesPath = () => routesMapping[ownerType]?.rolesPath({slug})

    return {
      slug,
      roleAssignmentsPath,
      newRoleAssignmentPath,
      rolesPath,
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
