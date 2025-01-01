import type {ReactNode} from 'react'
import {SecurityCampaignFormWrapper} from '../SecurityCampaignFormWrapper'
import {getUser} from '../../test-utils/mock-data'
import type {User} from '../../types/user'
import type {SecurityCampaign} from '../../types/security-campaign'

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
    <SecurityCampaignFormWrapper
      initialValues={campaign}
      currentUser={currentUser}
      maxManagers={10}
      allowDueDateInPast={false}
      submitForm={() => {}}
      reset={() => {}}
      isPending={false}
      formError={null}
    >
      {children}
    </SecurityCampaignFormWrapper>
  )
}
