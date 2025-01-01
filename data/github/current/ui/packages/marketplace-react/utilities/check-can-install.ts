import type {PlanInfo} from '../types'

type CheckCanInstallResult =
  | {
      canInstall: true
      reason: null
    }
  | {
      canInstall: false
      reason: string
    }

/**
 * Checks if the current user is able to install the app,
 * giving a reason if they are not able to.
 * @param planInfo The plan information for the app
 * @returns The result of the check
 * @see {@link PlanInfo}
 */
export default function checkCanInstall(planInfo: PlanInfo): CheckCanInstallResult {
  if (planInfo.isRegularEmuUser) {
    return {
      canInstall: false,
      reason: 'Only enterprise administrators and organization admins can purchase applications from the marketplace.',
    }
  } else if (planInfo.emuOwnerButNotAdmin) {
    return {
      canInstall: false,
      reason: 'Only enterprise admins are able to install paid Marketplace plans.',
    }
  }

  return {
    canInstall: true,
    reason: null,
  }
}
