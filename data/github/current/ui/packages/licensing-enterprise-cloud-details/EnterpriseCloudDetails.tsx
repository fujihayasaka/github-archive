import {Breadcrumbs, Heading, Stack} from '@primer/react'
import {NavigationContextProvider, useNavigation} from '@github-ui/licensing-common/contexts/NavigationContext'
import {EnterpriseCloudPaymentSummary} from '@github-ui/licensing-common/components/EnterpriseCloudPaymentSummary'
import {EnterpriseCloudUsageSummary} from '@github-ui/licensing-common/components/EnterpriseCloudUsageSummary'
import {LicenseeListContainer} from './components/LicenseeListContainer'
import {SummarySection} from './components/SummarySection'
import type {TrialInfo} from '@github-ui/licensing-common/types/trial-info'

export interface EnterpriseCloudDetailsProps {
  billingTermEndDate: string
  canViewMembers: boolean
  currentPayment: string
  enterpriseContactUrl: string
  enterpriseLicensesBillable: number
  enterpriseLicensesConsumed: number
  enterpriseLicensesPurchased: number
  isMonthly: boolean
  isVolumeLicensed: boolean
  isVssEnabled: boolean
  slug: string
  trialInfo?: TrialInfo
  unitCost: string
  vssLicensesConsumed: number
  vssLicensesPurchasedWithOverage: number
}

export function EnterpriseCloudDetails(props: EnterpriseCloudDetailsProps) {
  const isTrial: boolean = !!props.trialInfo

  return (
    <NavigationContextProvider {...props}>
      <div className="mb-4" data-testid="licensing-cloud-details">
        <Header />
        <Stack justify="space-between" direction="horizontal" className="mt-2 mb-3">
          <Heading as="h1">Enterprise Cloud</Heading>
        </Stack>
        <SummarySection
          summaries={[
            <EnterpriseCloudUsageSummary
              key="usage-summary"
              canViewMembers={props.canViewMembers}
              headingAs="h2"
              isTrial={isTrial}
              isVolumeLicensed={props.isVolumeLicensed}
              enterpriseLicensesConsumed={props.enterpriseLicensesConsumed}
              enterpriseLicensesPurchased={props.enterpriseLicensesPurchased}
              vssLicensesConsumed={props.vssLicensesConsumed}
              vssLicensesPurchasedWithOverage={props.vssLicensesPurchasedWithOverage}
              isVssEnabled={props.isVssEnabled}
            />,
            <EnterpriseCloudPaymentSummary
              key="payment-summary"
              billingTermEndDate={props.billingTermEndDate}
              currentPayment={props.currentPayment}
              enterpriseLicensesBillable={props.enterpriseLicensesBillable}
              headingAs="h2"
              isMonthly={props.isMonthly}
              isTrial={isTrial}
              isVolumeLicensed={props.isVolumeLicensed}
              isVssEnabled={props.isVssEnabled}
              unitCost={props.unitCost}
            />,
          ]}
        />
        <LicenseeListContainer isVolumeLicensed={props.isVolumeLicensed} />
      </div>
    </NavigationContextProvider>
  )
}

function Header() {
  const {basePath} = useNavigation()
  return (
    <Breadcrumbs>
      <Breadcrumbs.Item href={`${basePath}/enterprise_licensing`}>Licensing</Breadcrumbs.Item>
      <Breadcrumbs.Item selected>Enterprise Cloud</Breadcrumbs.Item>
    </Breadcrumbs>
  )
}
