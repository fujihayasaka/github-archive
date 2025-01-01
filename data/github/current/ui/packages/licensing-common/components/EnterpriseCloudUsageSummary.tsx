import {EnterpriseCloudSeatCount} from './EnterpriseCloudSeatCount'
import {UsageHint} from './UsageHint'
import {UsageSummary} from './UsageSummary'
import type {HeadingTag} from '../types/heading-tag'

export interface EnterpriseCloudUsageSummaryProps {
  canViewMembers: boolean
  enterpriseLicensesConsumed: number
  enterpriseLicensesPurchased: number
  headingAs?: HeadingTag
  isTrial: boolean
  isVolumeLicensed: boolean
  isVssEnabled: boolean
  vssLicensesConsumed: number
  vssLicensesPurchasedWithOverage: number
}
export function EnterpriseCloudUsageSummary(props: EnterpriseCloudUsageSummaryProps) {
  let usageSummaryDescription = props.isVolumeLicensed
    ? 'Organization members, outside collaborators, and pending invitations consume enterprise licenses.'
    : 'Organization members and outside collaborators consume enterprise licenses.'
  if (props.isVssEnabled) {
    usageSummaryDescription += ' Users matched to a Visual Studio assignment consume a Visual Studio license.'
  }

  return (
    <UsageSummary
      title="Consumed licenses"
      headingAs={props.headingAs}
      usageHint={
        <UsageHint
          title="Consumed licenses"
          label="About consumed licenses"
          description={usageSummaryDescription}
          learnMoreUrl="https://docs.github.com/en/enterprise-cloud@latest/billing/managing-the-plan-for-your-github-account/about-per-user-pricing"
        />
      }
    >
      <EnterpriseCloudSeatCount
        canViewMembers={props.canViewMembers}
        isTrial={props.isTrial}
        isVolumeLicensed={props.isVolumeLicensed}
        enterpriseLicensesConsumed={props.enterpriseLicensesConsumed}
        enterpriseLicensesPurchased={props.enterpriseLicensesPurchased}
        vssLicensesConsumed={props.vssLicensesConsumed}
        vssLicensesPurchasedWithOverage={props.vssLicensesPurchasedWithOverage}
      />
      {props.vssLicensesPurchasedWithOverage <= 0 && ( // hide here for VSS because the description ends up too long (still in usage hint)
        <div className="f6 color-fg-muted mt-1">{usageSummaryDescription}</div>
      )}
    </UsageSummary>
  )
}
