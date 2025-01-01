import {screen} from '@testing-library/react'

import {graphql} from 'react-relay'
import {EditIssueFieldsSection} from '../FieldsSection'
import type {MockResolvers} from 'relay-test-utils/lib/RelayMockPayloadGenerator'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {FieldsSectionTestQuery} from './__generated__/FieldsSectionTestQuery.graphql'

const renderFieldsSection = (mockResolvers?: MockResolvers) => {
  const {relayMockEnvironment, user} = renderRelay<{
    fields: FieldsSectionTestQuery
    fieldPicker: FieldsSectionTestQuery
  }>(
    ({queryData}) => <EditIssueFieldsSection issue={queryData.fields.repository!.issue!} singleKeyShortcutsEnabled />,
    {
      relay: {
        queries: {
          fields: {
            type: 'fragment',
            query: graphql`
              query FieldsSectionTestQuery($owner: String!, $repo: String!, $number: Int!) @relay_test_operation {
                repository(owner: $owner, name: $repo) {
                  issue(number: $number) {
                    ...FieldsSectionFragment
                  }
                }
              }
            `,
            variables: {owner: 'owner', repo: 'repo', number: 1},
          },
          fieldPicker: {
            type: 'lazy',
          },
        },
        mockResolvers,
      },
    },
  )

  return {relayMockEnvironment, user}
}

test('renders "Add field" button when no fields are present', async () => {
  renderFieldsSection({
    Issue: () => ({
      id: 'issue-1',
      repository: {
        owner: {
          login: 'owner',
        },
      },
      issueFieldValues: {
        nodes: [],
      },
    }),
  })

  expect(screen.getByRole('button', {name: 'Add field'})).toBeInTheDocument()
})

test('renders text field editor when text field value exists', async () => {
  renderFieldsSection({
    Issue: () => ({
      id: 'issue-1',
      repository: {
        owner: {
          login: 'owner',
        },
      },
      issueFieldValues: {
        nodes: [
          {
            __typename: 'IssueFieldTextValue',
            id: 'field-value-1',
            field: {
              __typename: 'IssueFieldText',
              id: 'field-1',
              name: 'Description',
              dataType: 'TEXT',
            },
            value: 'Sample text value',
          },
        ],
      },
    }),
  })

  expect(screen.getByDisplayValue('Sample text value')).toBeInTheDocument()
  expect(screen.getByText('Description')).toBeInTheDocument()
})

test('renders single select field editor when single select field value exists', async () => {
  renderFieldsSection({
    Issue: () => ({
      id: 'issue-1',
      repository: {
        owner: {
          login: 'owner',
        },
      },
      issueFieldValues: {
        nodes: [
          {
            __typename: 'IssueFieldSingleSelectValue',
            id: 'field-value-1',
            field: {
              __typename: 'IssueFieldSingleSelect',
              id: 'field-1',
              name: 'Priority',
              dataType: 'SINGLE_SELECT',
            },
            name: 'High',
            description: 'High priority',
            color: 'RED',
          },
        ],
      },
    }),
  })

  expect(screen.getByText('Priority')).toBeInTheDocument()
  expect(screen.getByText('High')).toBeInTheDocument()
})

test('renders multiple field types together', async () => {
  renderFieldsSection({
    Issue: () => ({
      id: 'issue-1',
      repository: {
        owner: {
          login: 'owner',
        },
      },
      issueFieldValues: {
        nodes: [
          {
            __typename: 'IssueFieldTextValue',
            id: 'field-value-1',
            field: {
              __typename: 'IssueFieldText',
              id: 'field-1',
              name: 'Description',
              dataType: 'TEXT',
            },
            value: 'Sample description',
          },
          {
            __typename: 'IssueFieldSingleSelectValue',
            id: 'field-value-2',
            field: {
              __typename: 'IssueFieldSingleSelect',
              id: 'field-2',
              name: 'Priority',
              dataType: 'SINGLE_SELECT',
            },
            name: 'High',
            description: 'High priority',
            color: 'RED',
          },
        ],
      },
    }),
  })

  // Both field types should be rendered
  expect(screen.getByDisplayValue('Sample description')).toBeInTheDocument()
  expect(screen.getByText('Description')).toBeInTheDocument()
  expect(screen.getByText('Priority')).toBeInTheDocument()
  expect(screen.getByText('High')).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Add field'})).toBeInTheDocument()
})

test('handles text field input changes', async () => {
  const {user} = renderFieldsSection({
    Issue: () => ({
      id: 'issue-1',
      repository: {
        owner: {
          login: 'owner',
        },
      },
      issueFieldValues: {
        nodes: [
          {
            __typename: 'IssueFieldTextValue',
            id: 'field-value-1',
            field: {
              __typename: 'IssueFieldText',
              id: 'field-1',
              name: 'Description',
              dataType: 'TEXT',
            },
            value: 'Initial value',
          },
        ],
      },
    }),
  })

  const textInput = screen.getByDisplayValue('Initial value')
  await user.clear(textInput)
  await user.type(textInput, 'Updated value')

  expect(screen.getByDisplayValue('Updated value')).toBeInTheDocument()
})
