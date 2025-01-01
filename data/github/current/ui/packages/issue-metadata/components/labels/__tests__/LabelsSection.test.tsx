import {Wrapper} from '@github-ui/react-core/test-utils'
import {screen, fireEvent, waitFor} from '@testing-library/react'
import {createMockEnvironment} from 'relay-test-utils'

import {EditIssueLabelsSection} from '../LabelsSection'
import {graphql} from 'react-relay'
import type {MockResolverContext, MockResolvers} from 'relay-test-utils/lib/RelayMockPayloadGenerator'
import type {LabelPickerQuery} from '@github-ui/item-picker/LabelPickerQuery.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {LabelsSectionTestQuery} from './__generated__/LabelsSectionTestQuery.graphql'
import {DefaultFeatureFlags as PrimerFeatureFlags} from '@primer/react/experimental'

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

  // select the row
  const optionName = PrimerFeatureFlags.flags.get('primer_react_select_panel_with_modern_action_list')
    ? 'mock label'
    : 'mock label mock description'
  const labelItem = screen.getByRole('option', {name: optionName})
  expect(labelItem).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(labelItem)

  // close the picker
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.keyDown(container, {key: 'Escape', keyCode: 'Escape'})

  expect(screen.queryByRole('option', {name: 'mock label'})).not.toBeInTheDocument()
})
