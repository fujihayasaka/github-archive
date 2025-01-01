import {act, screen, within} from '@testing-library/react'
import {createMockEnvironment} from 'relay-test-utils'

import {graphql} from 'react-relay'
import {
  CreateIssueIssueTypesSection,
  EditIssueIssueTypeSection,
  type CreateIssueIssueTypesSectionProps,
} from '../TypesSection'
import {TEST_IDS} from '../../../constants/test-ids'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {MockResolvers} from 'relay-test-utils/lib/RelayMockPayloadGenerator'
import {noop} from '@github-ui/noop'
import {Wrapper} from '@github-ui/react-core/test-utils'
import type {TypesSectionTestQuery} from './__generated__/TypesSectionTestQuery.graphql'
import type {IssueTypePickerQuery} from '@github-ui/item-picker/IssueTypePickerQuery.graphql'

const renderEditIssueIssueTypeSection = (mockResolvers: MockResolvers) => {
  const environment = createMockEnvironment()

  renderRelay<{issueTypes: TypesSectionTestQuery; issueTypePicker: IssueTypePickerQuery}>(
    ({queryData}) => (
      <EditIssueIssueTypeSection issue={queryData.issueTypes.repository!.issue!} singleKeyShortcutsEnabled />
    ),
    {
      relay: {
        queries: {
          issueTypes: {
            type: 'fragment',
            query: graphql`
              query TypesSectionTestQuery($owner: String!, $repo: String!, $number: Int!) {
                repository(owner: $owner, name: $repo) {
                  issue(number: $number) {
                    ...TypesSectionFragment
                  }
                }
              }
            `,
            variables: {owner: 'owner', repo: 'repo', number: 1},
          },
          issueTypePicker: {
            type: 'lazy',
          },
        },
        mockResolvers,
        environment,
      },
    },
  )

  return environment
}

describe('EditIssueIssueTypeSection', () => {
  describe('Button conditional rendering for permissions', () => {
    test('renders no buttons without permissions', async () => {
      renderEditIssueIssueTypeSection({
        Issue: () => ({
          issueType: null,
          viewerCanType: false,
        }),
      })

      expect(screen.queryByText('Edit Type')).not.toBeInTheDocument()
    })

    test('renders type edit button', async () => {
      renderEditIssueIssueTypeSection({
        Issue: () => ({
          issueType: null,
          viewerCanType: true,
        }),
      })

      expect(await screen.findByText('Edit Type')).toBeInTheDocument()
    })
  })

  test('renders types data', async () => {
    renderEditIssueIssueTypeSection({
      IssueType: () => ({
        name: 'Bug',
      }),
    })

    // Find the type
    const type = await screen.findByTestId(TEST_IDS.typeContainer)
    expect(within(type).getAllByText('Bug').length).toBe(1)
  })
})

const renderCreateIssueIssueTypesSection = ({
  mockResolvers,
  props,
}: {
  mockResolvers?: MockResolvers
  props?: Partial<CreateIssueIssueTypesSectionProps>
}) => {
  const environment = createMockEnvironment()

  renderRelay<{typePicker: IssueTypePickerQuery}>(
    () => (
      <CreateIssueIssueTypesSection
        repo="issues"
        owner="github"
        type={null}
        onSelectionChange={noop}
        viewerCanType={false}
        insidePortal={false}
        shortcutEnabled={false}
        {...props}
      />
    ),
    {
      relay: {
        queries: {
          typePicker: {
            type: 'lazy',
          },
        },
        mockResolvers,
        environment,
      },
      wrapper: Wrapper,
    },
  )

  return environment
}

describe('CreateIssueIssueTypesSection', () => {
  test('renders active type if viewer can type', () => {
    renderCreateIssueIssueTypesSection({
      props: {
        viewerCanType: true,
        type: {
          id: '1',
          isEnabled: false,
          name: 'Bug',
          description: 'description',
          color: 'RED',
          ' $fragmentType': 'IssueTypePickerIssueType',
        },
      },
    })

    expect(screen.getByText('Bug')).toBeInTheDocument()
  })

  test('renders edit button when permitted', () => {
    renderCreateIssueIssueTypesSection({
      props: {
        viewerCanType: true,
      },
    })

    expect(screen.getByRole('button', {name: 'Edit Type'})).toBeInTheDocument()
  })

  test('callback is called when selecting type', () => {
    const onSelectMock = jest.fn()
    renderCreateIssueIssueTypesSection({
      mockResolvers: {
        IssueType: () => ({
          id: '1',
          isEnabled: false,
          name: 'Bug',
          description: 'description',
          color: 'RED',
        }),
      },
      props: {
        viewerCanType: true,
        onSelectionChange: onSelectMock,
      },
    })

    act(() => screen.getByRole('button', {name: 'Edit Type'}).click())

    expect(onSelectMock).not.toHaveBeenCalled()

    act(() => screen.getByText('Bug').click())

    expect(onSelectMock).toHaveBeenCalledTimes(1)
  })
})
