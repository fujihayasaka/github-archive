import {Stack} from '@primer/react'
import {CopilotUsageSummary} from '@github-ui/licensing-common/components/CopilotUsageSummary'
import {CopilotPaymentSummary} from '@github-ui/licensing-common/components/CopilotPaymentSummary'
import type {Sku} from '@github-ui/licensing-common/copilot-types'
import type {Organization, User} from './types'
import {clsx} from 'clsx'
import styles from './CopilotDetails.module.css'

import {CopilotAccessList} from './components/CopilotAccessList'
import {CopilotDangerZone} from './components/CopilotDangerZone'
import {CopilotLicensingHeader} from './components/CopilotLicensingHeader'
import {CopilotOrganizationGeneralAccessDropdown} from './components/organizations/CopilotOrganizationGeneralAccessDropdown'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'

export interface CopilotDetailsProps {
  copilotDetails: {
    skus: Sku[]
    billingTermEndDate: string
    totalCost: number
    enablementSetting: string
    enabledOrganizationCount: number
    enabledUserCount: number
  }
  slug: string
  enterpriseContactUrl: string
  isStafftools: boolean
  isTeams: boolean
  organizations: {
    withCopilotAccess: Organization[]
    withoutCopilotAccess: Organization[]
  }
  users: {
    withCopilotAccess: User[]
  }
  isCopilotUserFlagEnabled: boolean
  isCopilotEnterpriseTeamsFlagEnabled: boolean
}

export function CopilotDetails({copilotDetails, ...props}: CopilotDetailsProps) {
  return (
    <NavigationContextProvider {...props}>
      <CopilotLicensingHeader />
      <div className="mb-4" data-testid="licensing-copilot-details">
        <Stack
          direction="horizontal"
          gap="spacious"
          className="pt-3 pb-0"
          align="stretch"
          data-testid="copilot-details"
        >
          <div className={clsx('Box', styles.box, 'p-3', styles.border)}>
            <CopilotUsageSummary skus={copilotDetails.skus} headingLevel="h2" />
          </div>
          <div className={clsx('Box', styles.box, 'p-3', styles.border)}>
            <CopilotPaymentSummary
              billingTermEndDate={copilotDetails.billingTermEndDate}
              skus={copilotDetails.skus}
              totalCost={copilotDetails.totalCost}
              headingLevel="h2"
            />
          </div>
        </Stack>
      </div>
      <CopilotOrganizationGeneralAccessDropdown enablementSetting={copilotDetails.enablementSetting} />
      <CopilotAccessList
        enabledOrganizationCount={copilotDetails.enabledOrganizationCount}
        enabledUserCount={copilotDetails.enabledUserCount}
        organizations={props.organizations}
        users={props.users}
        isCopilotUserFlagEnabled={props.isCopilotUserFlagEnabled}
        isCopilotEnterpriseTeamsFlagEnabled={props.isCopilotEnterpriseTeamsFlagEnabled}
      />
      <CopilotDangerZone />
    </NavigationContextProvider>
  )
}
