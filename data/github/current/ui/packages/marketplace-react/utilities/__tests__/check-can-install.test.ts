import checkCanInstall from '../check-can-install'
import {mockPlanInfo} from '../../test-utils/mock-data'

describe('checkCanInstall', () => {
  it('should return canInstall: false with reason for regular EMU user', () => {
    const planInfo = mockPlanInfo({isRegularEmuUser: true})
    const result = checkCanInstall(planInfo)
    expect(result).toEqual({
      canInstall: false,
      reason: 'Only enterprise administrators and organization admins can purchase applications from the marketplace.',
    })
  })

  it('should return canInstall: false with reason for EMU owner but not admin', () => {
    const planInfo = mockPlanInfo({emuOwnerButNotAdmin: true})
    const result = checkCanInstall(planInfo)
    expect(result).toEqual({
      canInstall: false,
      reason: 'Only enterprise admins are able to install paid Marketplace plans.',
    })
  })

  it('should return canInstall: false with reason for regular EMU user and EMU owner but not admin', () => {
    const planInfo = mockPlanInfo({isRegularEmuUser: true, emuOwnerButNotAdmin: true})
    const result = checkCanInstall(planInfo)
    expect(result).toEqual({
      canInstall: false,
      reason: 'Only enterprise administrators and organization admins can purchase applications from the marketplace.',
    })
  })

  it('should return canInstall: true with no reason for eligible user', () => {
    const planInfo = mockPlanInfo({isRegularEmuUser: false, emuOwnerButNotAdmin: false})
    const result = checkCanInstall(planInfo)
    expect(result).toEqual({
      canInstall: true,
      reason: null,
    })
  })
})
