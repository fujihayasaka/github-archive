import type {Meta} from '@storybook/react'
import {EditIssueFieldsSection, type EditIssueFieldsSectionProps} from './FieldsSection'
import {noop} from '@github-ui/noop'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'relay-runtime'
import {makeIssueMetadataFields} from '../../test-utils/mocks'
import type {FieldsSectionStoryQuery} from './__generated__/FieldsSectionStoryQuery.graphql'

type FieldsSectionQueries = {
  fieldsQuery: FieldsSectionStoryQuery
}

const meta = {
  title: 'IssuesComponents/IssueMetadata/Sections',
  component: EditIssueFieldsSection,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof EditIssueFieldsSection>

export default meta

const defaultArgs: Partial<EditIssueFieldsSectionProps> = {
  onIssueUpdate: noop,
  singleKeyShortcutsEnabled: false,
}

export const FieldsSectionExample = {
  decorators: [relayDecorator<typeof EditIssueFieldsSection, FieldsSectionQueries>],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        fieldsQuery: {
          type: 'fragment',
          query: graphql`
            query FieldsSectionStoryQuery($owner: String!, $repo: String!, $number: Int!) @relay_test_operation {
              repository(owner: $owner, name: $repo) {
                issue(number: $number) {
                  ...FieldsSectionFragment
                }
              }
            }
          `,
          variables: {owner: 'organization', repo: 'repository', number: 123},
        },
      },
      mockResolvers: makeIssueMetadataFields(),
      mapStoryArgs: ({queryData}) => ({
        issue: queryData.fieldsQuery.repository!.issue!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof EditIssueFieldsSection, FieldsSectionQueries>
