import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'

export function buildAssignee({
  login,
  name,
  typename = 'User',
  isCopilot = false,
}: {
  login: string
  name: string
  typename?: string
  isCopilot?: boolean
}) {
  return {
    id: mockRelayId(),
    login,
    name,
    avatarUrl: '',
    __typename: typename,
    isCopilot,
  }
}
