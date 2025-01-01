import {renderHook, waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {useFetchFilterSuggestedIssueTypes} from '../../client/hooks/use-fetch-filter-suggested-issue-types'
import {createTestEnvironment} from '../test-app-wrapper'

const Wrapper: React.ComponentType<React.PropsWithChildren> = ({children}) => {
  createTestEnvironment({
    'memex-owner': {
      id: 1,
      login: 'github',
      name: 'GitHub',
      avatarUrl: 'https://foo.bar/avatar.png',
      type: 'organization',
    },
  })

  const environment = setupRelayEnvironment()
  return <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
}

describe('useFetchFilterSuggestedIssueTypes', () => {
  it('returns suggestions for memex owner issue types', async () => {
    const {result} = renderHook(useFetchFilterSuggestedIssueTypes, {
      wrapper: Wrapper,
    })

    await waitFor(() =>
      expect(result.current.suggestedIssueTypeNames).toEqual(['Batch', 'Epic', 'Must-have', 'Nice-to-have', 'Stretch']),
    )
  })
})

const setupRelayEnvironment = () => {
  const relayEnvironment = createMockEnvironment()
  relayEnvironment.mock.queueOperationResolver((operation: OperationDescriptor) =>
    MockPayloadGenerator.generate(operation, {
      Organization: () => {
        return {
          projectV2: {
            suggestedIssueTypeNames: ['Batch', 'Epic', 'Must-have', 'Nice-to-have', 'Stretch'],
          },
        }
      },
    }),
  )

  return relayEnvironment
}
