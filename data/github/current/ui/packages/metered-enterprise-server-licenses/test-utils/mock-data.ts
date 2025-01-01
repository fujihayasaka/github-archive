import type {Props as MeteredEnterpriseServerLicensesProps} from '../MeteredEnterpriseServerLicenses'

export function getEmptyMeteredEnterpriseServerLicensesProps(): MeteredEnterpriseServerLicensesProps {
  return {
    business: {slug: 'github-inc'},
    isGhasBundled: true,
    enableGhasBundleMismatchWarning: false,
    serverLicenses: [],
    consumedEnterpriseLicenses: 0,
  }
}

export function getMeteredEnterpriseServerLicensesProps(): MeteredEnterpriseServerLicensesProps {
  return {
    business: {slug: 'github-inc'},
    isGhasBundled: true,
    enableGhasBundleMismatchWarning: false,
    serverLicenses: [
      {
        reference_number: 'abc123',
        seats: 50,
        expires_at: '2030-01-01',
        code_security_enabled: false,
        secret_protection_enabled: false,
      },
    ],
    consumedEnterpriseLicenses: 50,
  }
}
