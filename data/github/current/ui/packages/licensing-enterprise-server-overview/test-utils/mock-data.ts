import type {EnterpriseServerSummaryProps} from '../components/EnterpriseServerSummary'

export function getEnterpriseServerOverviewProps() {
  return {
    ghesUsage: getEnterpriseServerSummaryProps(),
  }
}

export function getEnterpriseServerSummaryProps(): EnterpriseServerSummaryProps {
  return {
    dueDate: '2024-06-30',
    hasEnterpriseServer: true,
    hasMeteredGhe: true,
    ghesLicenseCount: 0,
    ghesBillableLicenseCount: 0,
    bundledGhasLicenseCount: 0,
    bundledGhasBillableLicenseCount: 0,
    codeSecurityLicenseCount: 0,
    codeSecurityBillableLicenseCount: 0,
    secretProtectionLicenseCount: 0,
    secretProtectionBillableLicenseCount: 0,
    ghesUnitPrice: 21,
    bundledGhasUnitPrice: 49,
    codeSecurityUnitPrice: 30,
    secretProtectionUnitPrice: 19,
  }
}
