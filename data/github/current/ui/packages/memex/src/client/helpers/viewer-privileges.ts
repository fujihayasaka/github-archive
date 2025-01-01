import {DefaultPrivileges, type Privileges, Role} from '../api/common-contracts'
import {getInitialState} from './initial-state'

/**
 * This helper function exposes the `Privileges` for the current user.
 * It encapsulates very basic logic initially but the scope can and will be extended to support granular permissions
 */
export const ViewerPrivileges = () => {
  const {viewerPrivileges, loggedInUser} = getInitialState()

  return {
    isLoggedIn: loggedInUser !== undefined,
    isReadonly: viewerPrivileges.role === Role.Read,
    hasWritePermissions: viewerPrivileges.role !== Role.Read,
    hasAdminPermissions: viewerPrivileges.role === Role.Admin,
    canChangeProjectVisibility: viewerPrivileges.canChangeProjectVisibility,
    // Default to true when server hasn't deployed canCopy yet, so "Make a copy"
    // isn't hidden during the deploy window between github-ui and github/github.
    canCopy: viewerPrivileges.canCopy ?? true,
    canCopyAsTemplate: viewerPrivileges.canCopyAsTemplate,
  }
}

/**
 * Provides an easy way to override a targeted subset of attributes from the DefaultPrivileges
 * object.
 *
 * Automatically sets `canCopy: true` for Write/Admin roles so that the 50+
 * existing call-sites passing only `{ role: Role.Write }` continue to work
 * without needing an explicit `canCopy: true`. Callers can still override
 * `canCopy` explicitly (e.g. `{ role: Role.Write, canCopy: false }`).
 *
 * @param overrides A subset of attributes to use instead of the default ones.
 * @returns Privileges object.
 */
export function overrideDefaultPrivileges(overrides: Partial<Privileges>): Privileges {
  const role = overrides.role ?? DefaultPrivileges.role
  const canCopy = overrides.canCopy ?? (role === Role.Write || role === Role.Admin)

  return {...DefaultPrivileges, ...overrides, canCopy}
}
