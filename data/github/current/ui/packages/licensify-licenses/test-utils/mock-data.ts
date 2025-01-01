import type {LicensifyLicensesProps} from '../LicensifyLicenses'

export function getLicensifyLicensesProps(): LicensifyLicensesProps {
  return {
    customerId: '1',
    licenseStatuses: [
      'LICENSE_STATUS_UNSPECIFIED',
      'LICENSE_STATUS_ACTIVE',
      'LICENSE_STATUS_DEACTIVATED',
      'LICENSE_STATUS_SUSPENDED',
    ],
  }
}
