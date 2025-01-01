import {BulkMarkAs} from './BulkMarkAs'
import type {Meta} from '@storybook/react'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {RelayEnvironmentProvider} from 'react-relay'
import {Suspense} from 'react'

// Create a mock Relay environment
const {environment} = createRelayMockEnvironment()

function EntryPoint() {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <Suspense fallback="...Loading">
        <TestComponent />
      </Suspense>
    </RelayEnvironmentProvider>
  )
}

function TestComponent() {
  return (
    <BulkMarkAs
      disabled={false}
      singleKeyShortcutsEnabled={false}
      issuesToActOn={[mockIssueId]}
      useQueryForAction={false}
    />
  )
}

const mockIssueId = 'issue-1'
const meta = {
  title: 'BulkActions/BulkMarkAs',
  component: BulkMarkAs,
  parameters: {
    controls: {
      expanded: true,
    },
  },
} satisfies Meta<typeof BulkMarkAs>

export default meta

export const Default = {
  args: {},
  render: () => {
    return <EntryPoint />
  },
}
