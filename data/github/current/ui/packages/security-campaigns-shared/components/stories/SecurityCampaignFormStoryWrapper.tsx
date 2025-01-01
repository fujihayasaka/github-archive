import type {ReactNode} from 'react'
import type {SecurityCampaign} from '../../types/security-campaign'
import type {User} from '../../types/user'
import {getUser} from '../../test-utils/mock-data'
import {SecurityCampaignFormWrapper} from '../SecurityCampaignFormWrapper'

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
