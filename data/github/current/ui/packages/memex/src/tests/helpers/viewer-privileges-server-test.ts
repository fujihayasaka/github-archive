import {DefaultPrivileges, Role} from '../../client/api/common-contracts'
import {overrideDefaultPrivileges} from '../../client/helpers/viewer-privileges'

describe('overrideDefaultPrivileges', () => {
  it('returns DefaultPrivileges when no overrides are provided', () => {
    const result = overrideDefaultPrivileges({})
    expect(result).toEqual({...DefaultPrivileges, canCopy: false})
  })

  it('auto-derives canCopy: true for Write role', () => {
    const result = overrideDefaultPrivileges({role: Role.Write})
    expect(result.canCopy).toBe(true)
  })

  it('auto-derives canCopy: true for Admin role', () => {
    const result = overrideDefaultPrivileges({role: Role.Admin})
    expect(result.canCopy).toBe(true)
  })

  it('auto-derives canCopy: false for Read role', () => {
    const result = overrideDefaultPrivileges({role: Role.Read})
    expect(result.canCopy).toBe(false)
  })

  it('auto-derives canCopy: false for None role', () => {
    const result = overrideDefaultPrivileges({role: Role.None})
    expect(result.canCopy).toBe(false)
  })

  it('honors explicit canCopy: false for Write role', () => {
    const result = overrideDefaultPrivileges({role: Role.Write, canCopy: false})
    expect(result.canCopy).toBe(false)
  })

  it('honors explicit canCopy: true for Read role', () => {
    const result = overrideDefaultPrivileges({role: Role.Read, canCopy: true})
    expect(result.canCopy).toBe(true)
  })

  it('applies other overrides alongside canCopy derivation', () => {
    const result = overrideDefaultPrivileges({
      role: Role.Write,
      canChangeProjectVisibility: true,
      canCopyAsTemplate: true,
    })
    expect(result).toEqual({
      role: Role.Write,
      canChangeProjectVisibility: true,
      canCopy: true,
      canCopyAsTemplate: true,
    })
  })
})
