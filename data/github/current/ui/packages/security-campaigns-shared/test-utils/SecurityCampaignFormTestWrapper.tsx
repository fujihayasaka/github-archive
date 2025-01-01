import {
  SecurityCampaignFormWrapper,
  type SecurityCampaignFormWrapperProps,
} from '../components/SecurityCampaignFormWrapper'
import {getUser} from '../test-utils/mock-data'

const defaultUser = getUser()

export function SecurityCampaignFormTestWrapper({children, ...props}: Partial<SecurityCampaignFormWrapperProps>) {
  return (
    <SecurityCampaignFormWrapper
      initialValues={undefined}
      currentUser={defaultUser}
      maxManagers={10}
      allowDueDateInPast={false}
      submitForm={() => {}}
      reset={() => {}}
      isPending={false}
      formError={null}
      {...props}
    >
      {children}
    </SecurityCampaignFormWrapper>
  )
}
