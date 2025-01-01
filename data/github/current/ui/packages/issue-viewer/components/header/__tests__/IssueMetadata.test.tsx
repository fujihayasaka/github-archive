import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'react-relay'
import {IssueMetadata} from '../IssueMetadata'
import type {IssueMetadataTestQuery} from './__generated__/IssueMetadataTestQuery.graphql'
import type {IssueMetadata$key} from '../__generated__/IssueMetadata.graphql'
import {screen} from '@testing-library/react'
import type {LabelPickerLabel$data} from '@github-ui/item-picker/LabelPickerLabel.graphql'
import type {AssigneePickerAssignee$data} from '@github-ui/item-picker/AssigneePicker.graphql'
import type {MilestonePickerMilestone$data} from '@github-ui/item-picker/MilestonePickerMilestone.graphql'

const setup = ({
  label,
  assignee,
  milestone,
}: {
  label?: LabelPickerLabel$data
  assignee?: AssigneePickerAssignee$data
  milestone?: MilestonePickerMilestone$data
}) => {
  return renderRelay<{issueMetadataQuery: IssueMetadataTestQuery}>(
    ({queryData}) => (
      <IssueMetadata metadataKey={queryData.issueMetadataQuery.repository?.issue as IssueMetadata$key} />
    ),
    {
      relay: {
        queries: {
          issueMetadataQuery: {
            type: 'fragment',
            query: graphql`
              query IssueMetadataTestQuery {
                repository(name: "repo", owner: "owner") {
                  issue(number: 42) {
                    ...IssueMetadata
                  }
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Issue() {
            return {
              labels: {
                edges: [
                  {
                    node: label ?? null,
                  },
                ],
              },
              assignees: {
                nodes: [assignee ?? null],
              },
              milestone: milestone ?? null,
            }
          },
        },
      },
    },
  )
}

const label = {
  id: 'label1',
  name: 'bug',
  color: 'd73a4a',
  nameHTML: 'bug',
  description: 'A bug',
  url: '/bug',
} as LabelPickerLabel$data

const assignee = {
  id: 'assignee1',
  login: 'octocat',
  avatarUrl: 'https://avatars.githubusercontent.com/u/583231?v=4',
  name: 'octocat',
} as AssigneePickerAssignee$data

const milestone = {
  id: 'milestone1',
  title: 'v1.0',
  url: '/milestone',
  closed: false,
  closedAt: null,
  dueOn: null,
  progressPercentage: 0,
} as MilestonePickerMilestone$data

describe('IssueMetadata', () => {
  test('Renders labels metadata if issue is labeled', async () => {
    setup({label})
    expect(screen.getByText('Labels')).toBeInTheDocument()
    expect(screen.getByText('bug')).toBeInTheDocument()
  })

  test('does not render labels metadata if issue is not labeled', async () => {
    setup({})
    expect(screen.queryByText('Labels')).not.toBeInTheDocument()
    expect(screen.queryByText('bug')).not.toBeInTheDocument()
  })

  test('Renders assignees metadata if issue is assigned', async () => {
    setup({assignee})
    expect(screen.getByText('Assignees')).toBeInTheDocument()
    expect(screen.getByAltText('octocat')).toBeInTheDocument()
  })

  test('does not render assignees metadata if issue is not assigned', async () => {
    setup({})
    expect(screen.queryByText('Assignees')).not.toBeInTheDocument()
    expect(screen.queryByAltText('octocat')).not.toBeInTheDocument()
  })

  test('Renders milestone metadata if issue has a milestone', async () => {
    setup({milestone})
    expect(screen.getByText('Milestone')).toBeInTheDocument()
    expect(screen.getByText('v1.0')).toBeInTheDocument()
  })

  test('does not render milestone metadata if issue has no milestone', async () => {
    setup({})
    expect(screen.queryByText('Milestone')).not.toBeInTheDocument()
    expect(screen.queryByText('v1.0')).not.toBeInTheDocument()
  })
})
