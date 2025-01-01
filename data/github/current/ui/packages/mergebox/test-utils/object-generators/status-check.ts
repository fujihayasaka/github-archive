import type {StatusCheck, StatusCheckState} from '../../page-data/payloads/status-checks'

export function StatusCheckGenerator({
  state,
  description = 'test description',
  displayName = 'test-status-check',
  isRequired = true,
  avatarUrl = 'https://github.com/primer/design/assets/7265547/24ed9399-ec5a-4160-8f4f-1f11dc560b15',
}: {
  state: StatusCheckState
  description?: string
  displayName?: string
  isRequired?: boolean
  avatarUrl?: string
}): StatusCheck {
  return {
    state,
    avatarUrl,
    displayName,
    additionalContext: '',
    description,
    durationInSeconds: 1000,
    isRequired,
    stateChangedAt: '2023-01-01T00:00:00Z',
    targetUrl: 'https://example.com/target',
  }
}
