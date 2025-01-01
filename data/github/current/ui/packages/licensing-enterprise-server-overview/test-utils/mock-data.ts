import type {EnterpriseServerSummaryProps} from '../components/EnterpriseServerSummary'

export function getEnterpriseServerOverviewProps() {
  return {
    ghesUsage: getEnterpriseServerSummaryProps(),
  }
}

export function getEnterpriseServerSummaryProps(): EnterpriseServerSummaryProps {
  return {
    dueDate: new Date('2024-06-30T00:00:00.000-07:00'),
    hasEnterpriseServer: true,
    ghesLicenseCount: 0,
    ghesBillableLicenseCount: 0,
    bundledGhasLicenseCount: 0,
    bundledGhasBillableLicenseCount: 0,
    codeSecurityLicenseCount: 0,
    codeSecurityBillableLicenseCount: 0,
    secretProtectionLicenseCount: 0,
    secretProtectionBillableLicenseCount: 0,
    ghesUnitPrice: 0,
    bundledGhasUnitPrice: 0,
    codeSecurityUnitPrice: 0,
    secretProtectionUnitPrice: 0,
  }
}
