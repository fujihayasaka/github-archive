// Budgets can be created, edited, and deleted by the following:
// Enterprise: Enterprise Owner, Enterprise Org Owner, Billing Manager

import {BILLING_MANAGER, ENTERPRISE_ORG_OWNER, OWNER, MEMBER} from '../constants'
import type {AdminRole} from '../types/common'

// Budgets can be created, edited, and deleted by the following:
// Enterprise: Enterprise Owner, Enterprise Org Owner, Billing Manager
// Organization: Organization Owner
// Trial customers and stafftools users cannot create, edit, or delete budgets
export const currentUserHasBudgetWritePermissions = (
  adminRoles: AdminRole[],
  isEnterprise: boolean,
  isStafftools: boolean,
  isTrialCustomer: boolean,
) => {
  if (isStafftools) {
    return false
  }

  if (isTrialCustomer) {
    return false
  }

  return (
    (adminRoles.includes(BILLING_MANAGER) && isEnterprise) ||
    (adminRoles.includes(BILLING_MANAGER) && adminRoles.includes(MEMBER) && !isEnterprise) ||
    adminRoles.includes(OWNER) ||
    adminRoles.includes(ENTERPRISE_ORG_OWNER)
  )
}
