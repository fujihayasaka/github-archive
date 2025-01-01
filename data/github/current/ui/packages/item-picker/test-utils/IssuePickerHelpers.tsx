import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {RelayEnvironmentProvider, graphql, useLazyLoadQuery} from 'react-relay'
import type React from 'react'
import type {createMockEnvironment} from 'relay-test-utils'
import {IssuePicker} from '../components/IssuePicker'
import type {IssuePickerHelpersTestQuery} from '../test-utils/__generated__/IssuePickerHelpersTestQuery.graphql'
import type {IssueState} from '../components/__generated__/IssuePickerIssue.graphql'
import {Button} from '@primer/react'

export type TestComponentProps = {
  environment: ReturnType<typeof createMockEnvironment>
  owner?: string
  repositoryNameWithOwner?: string
  title?: string
  triggerOpen?: boolean
  hiddenIssueIds?: string[]
  selectedIssueIds?: string[]
} & Pick<React.ComponentProps<typeof IssuePicker>, 'isLoading'>

export function TestIssuePickerComponent({environment, ...props}: TestComponentProps) {
  return (
    <RelayEnvironmentProvider environment={environment}>
      <Component {...props} />
    </RelayEnvironmentProvider>
  )
}

export const IssuePickerHelpers_TestQuery = graphql`
  query IssuePickerHelpersTestQuery @relay_test_operation {
    issue: node(id: "test-issue-id") {
      ... on Issue {
        subIssues(first: 100) {
          nodes {
            id
          }
        }
      }
    }
  }
`

function Component(props: Omit<TestComponentProps, 'environment'>) {
  const issue = useLazyLoadQuery<IssuePickerHelpersTestQuery>(IssuePickerHelpers_TestQuery, {})

  const hiddenIssueIds = issue.issue?.subIssues?.nodes?.filter(node => !!node).map(issueData => issueData.id)

  return (
    <IssuePicker
      hiddenIssueIds={hiddenIssueIds ?? []}
      onIssueSelection={() => {}}
      anchorElement={(anchorProps: React.HTMLAttributes<HTMLElement>) => (
        <Button {...anchorProps}>Open Issue Picker</Button>
      )}
      {...props}
    />
  )
}

function getRandomNumber() {
  return Math.ceil(Math.random() * 1000)
}

export function buildIssue({title, number, repoId}: {title: string; number?: number; repoId?: string}) {
  return {
    id: mockRelayId(),
    databaseId: getRandomNumber(),
    title,
    number: number !== undefined ? number : getRandomNumber(),
    closed: false,
    repository: {
      id: repoId ?? '123',
      nameWithOwner: 'github/issues',
    },
    state: 'OPEN' as IssueState,
    stateReason: null,
    __typename: 'Issue',
  }
}
