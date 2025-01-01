import {isStaff} from '@github-ui/stats'

export function isDevelopmentOrStaffUser() {
  return process.env.NODE_ENV === 'development' || isStaff()
}
