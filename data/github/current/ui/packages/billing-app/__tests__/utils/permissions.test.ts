import type {AdminRole} from '../../types/common'
import {currentUserHasBudgetWritePermissions} from '../../utils/permissions'

describe('currentUserHasBudgetWritePermissions', () => {
  it('returns true when user is enterprise org owner', () => {
    const adminRoles: AdminRole[] = ['enterprise_org_owner']
    const isEnterprise = true
    const isStafftools = false
    const isTrialCustomer = false
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeTruthy()
  })

  it('returns true when user is owner and is enterprise', () => {
    const adminRoles: AdminRole[] = ['owner']
    const isEnterprise = true
    const isStafftools = false
    const isTrialCustomer = false
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeTruthy()
  })

  it('returns true when user is owner and is not enterprise', () => {
    const adminRoles: AdminRole[] = ['owner']
    const isEnterprise = false
    const isStafftools = false
    const isTrialCustomer = false
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeTruthy()
  })

  it('returns true when user is billing manager and is enterprise', () => {
    const adminRoles: AdminRole[] = ['billing_manager']
    const isEnterprise = true
    const isStafftools = false
    const isTrialCustomer = false
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeTruthy()
  })

  it('returns false when user is billing manager and is not enterprise', () => {
    const adminRoles: AdminRole[] = ['billing_manager']
    const isEnterprise = false
    const isStafftools = false
    const isTrialCustomer = false
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeFalsy()
  })

  it('returns false when is stafftools route', () => {
    const adminRoles: AdminRole[] = []
    const isEnterprise = false
    const isStafftools = true
    const isTrialCustomer = false
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeFalsy()
  })

  it('returns false when is trial customer', () => {
    const adminRoles: AdminRole[] = ['owner']
    const isEnterprise = false
    const isStafftools = false
    const isTrialCustomer = true
    expect(currentUserHasBudgetWritePermissions(adminRoles, isEnterprise, isStafftools, isTrialCustomer)).toBeFalsy()
  })
})
