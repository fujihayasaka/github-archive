import {setupUserEvent, Wrapper} from '@github-ui/react-core/test-utils'
import {fireEvent, screen, waitFor, within} from '@testing-library/react'
import {createMockEnvironment} from 'relay-test-utils'

import {mockClientEnv} from '@github-ui/client-env/mock'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {LabelPickerQuery} from '@github-ui/item-picker/LabelPickerQuery.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {graphql} from 'react-relay'
import type {MockResolverContext, MockResolvers} from 'relay-test-utils/lib/RelayMockPayloadGenerator'
import {EditIssueLabelsSection} from '../LabelsSection'
import type {LabelsSectionTestQuery} from './__generated__/LabelsSectionTestQuery.graphql'

jest.mock('@github-ui/hydro-analytics', () => ({
  sendEvent: jest.fn(),
}))

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const renderLabelsSection = (mockResolvers?: MockResolvers) => {
  const environment = createMockEnvironment()

  const {container} = renderRelay<{labels: LabelsSectionTestQuery; labelPicker: LabelPickerQuery}>(
    ({queryData}) => <EditIssueLabelsSection issue={queryData.labels.repository!.issue!} singleKeyShortcutsEnabled />,
    {
      relay: {
        queries: {
          labels: {
            type: 'fragment',
            query: graphql`
              query LabelsSectionTestQuery($owner: String!, $repo: String!, $number: Int!) @relay_test_operation {
                repository(owner: $owner, name: $repo) {
                  # eslint-disable-next-line relay/unused-fields
                  issue(number: $number) {
                    ...LabelsSectionFragment
                  }
                }
              }
            `,
            variables: {owner: 'owner', repo: 'repo', number: 1},
          },
          labelPicker: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          // Label colour mock
          String: (context: MockResolverContext) => {
            if (context.name === 'color') {
              return '000'
            }
          },
          ...mockResolvers,
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  return {environment, container}
}

test('renders no buttons without permissions', async () => {
  renderLabelsSection({
    Issue: () => ({
      repository: {isArchived: true},
      viewerCanUpdate: true,
      viewerCanLabel: false,
    }),
  })

  expect(screen.queryByText(/Edit Labels/)).not.toBeInTheDocument()
})

test('renders label edit button when permitted and labels are loaded', async () => {
  renderLabelsSection({
    Issue: () => ({
      viewerCanLabel: true,
    }),
  })

  expect(screen.getByText('Edit Labels')).toBeInTheDocument()
})

test('triggers callback on change', async () => {
  const {container} = renderLabelsSection({
    Issue: () => ({
      viewerCanLabel: true,
    }),
    LabelConnection: context => {
      // Mock label connection only for the label picker, not for Issue
      if (context.path?.join('/') === 'repository/labels') {
        return {
          nodes: [
            {
              name: 'mock label',
              nameHTML: 'mock label',
              description: 'mock description',
            },
          ],
        }
      }
    },
  })

  const pickerAnchor = screen.getByText('Edit Labels')
  expect(pickerAnchor).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(pickerAnchor)

  // select the first first label
  await waitFor(() => {
    expect(screen.getByRole('listbox')).toBeInTheDocument()
  })

  const labelItem = await screen.findByText('mock label', {selector: 'span'})
  expect(labelItem).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(labelItem)

  // close the picker
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.keyDown(container, {key: 'Escape', keyCode: 'Escape'})

  expect(screen.queryByRole('option', {name: 'mock label'})).not.toBeInTheDocument()
})

test('renders label picker with hotkeys', async () => {
  renderLabelsSection({
    Issue: () => ({
      viewerCanLabel: true,
    }),
  })

  expect(screen.getByText('Edit Labels')).toBeInTheDocument()

  const user = setupUserEvent()

  await user.keyboard('l')
  const dialog = within(screen.getByRole('dialog'))

  expect(dialog.getByText('Apply labels to this issue')).toBeInTheDocument()

  const input = dialog.getByRole('combobox')
  expect(input).toHaveTextContent('')
})

test('sends skipped event when manually selecting labels with copilot enabled', async () => {
  jest.mocked(isFeatureEnabled).mockReturnValue(true)
  mockClientEnv({
    featureFlags: ['copilot_auto_assign_metadata'],
  })
  expect(isFeatureEnabled('copilot_auto_assign_metadata')).toBe(true)

  const user = setupUserEvent()
  const {container} = renderLabelsSection({
    Issue: () => ({
      id: 'TEST_ISSUE_ID',
      viewerCanLabel: true,
      // repository not archived so we have permission
      repository: {isArchived: false},
      // no existing labels triggers Copilot
      labels: {edges: []},
    }),
    LabelConnection: context => {
      if (context.path?.join('/') === 'repository/labels') {
        return {
          nodes: [
            {
              name: 'test-label',
              nameHTML: 'test-label',
              description: 'test description',
            },
          ],
        }
      }
    },
  })

  // open the label picker
  await user.click(screen.getByText('Edit Labels'))
  // wait for the label list
  await expect(screen.findByRole('listbox')).resolves.toBeInTheDocument()

  const label = await screen.findByText('test-label', {selector: 'span'})
  expect(label).toBeInTheDocument()
  // select a label by its actual accessible name
  await user.click(label)
  // close the picker
  await user.type(container, '{Escape}')

  expect(sendEvent).toHaveBeenCalledWith(
    'copilot_suggested_labels.skipped',
    expect.objectContaining({issueId: 'TEST_ISSUE_ID'}),
  )
})
