import type {ReactNode} from 'react'
import type {SecurityCampaign} from '../../types/security-campaign'
import type {User} from '../../types/user'
import {getUser} from '../../test-utils/mock-data'
import {SecurityCampaignFormWrapper} from '../SecurityCampaignFormWrapper'
import {TestWrapper} from '../../test-utils/TestWrapper'

export type SecurityCampaignFormStoryWrapperProps = {
  campaign?: SecurityCampaign
  currentUser?: User
  children: ReactNode
}

const defaultUser = getUser()

export function SecurityCampaignFormStoryWrapper({
  campaign,
  children,
  currentUser = defaultUser,
}: SecurityCampaignFormStoryWrapperProps) {
  return (
    <TestWrapper>
      <SecurityCampaignFormWrapper
        campaign={campaign}
        currentUser={currentUser}
        allowDueDateInPast={false}
        submitForm={() => {}}
        reset={() => {}}
        isPending={false}
        formError={null}
      >
        {children}
      </SecurityCampaignFormWrapper>
    </TestWrapper>
  )
}
