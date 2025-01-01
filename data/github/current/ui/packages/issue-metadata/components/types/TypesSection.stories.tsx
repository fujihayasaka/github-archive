import type {Meta} from '@storybook/react'
import {EditIssueIssueTypeSection} from './TypesSection'
import {noop} from '@github-ui/noop'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {makeIssueMetadataFields} from '../../test-utils/mocks'
import {graphql} from 'relay-runtime'
import type {TypesSectionStoryQuery} from './__generated__/TypesSectionStoryQuery.graphql'

type TypesSectionQueries = {
  typesQuery: TypesSectionStoryQuery
}

const meta = {
  title: 'IssuesComponents/IssueMetadata/Sections',
  component: EditIssueIssueTypeSection,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof EditIssueIssueTypeSection>

export default meta

const defaultArgs: Partial<typeof EditIssueIssueTypeSection> = {
  onIssueUpdate: noop,
  singleKeyShortcutsEnabled: false,
}

export const TypesSectionExample = {
  decorators: [relayDecorator<typeof EditIssueIssueTypeSection, TypesSectionQueries>],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        typesQuery: {
          type: 'fragment',
          query: graphql`
            query TypesSectionStoryQuery($owner: String!, $repo: String!, $number: Int!) @relay_test_operation {
              repository(owner: $owner, name: $repo) {
                issue(number: $number) {
                  ...TypesSectionFragment
                }
              }
            }
          `,
          variables: {owner: 'organization', repo: 'repository', number: 123},
        },
      },
      mockResolvers: makeIssueMetadataFields(),
      mapStoryArgs: ({queryData}) => ({
        issue: queryData.typesQuery.repository!.issue!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof EditIssueIssueTypeSection, TypesSectionQueries>
