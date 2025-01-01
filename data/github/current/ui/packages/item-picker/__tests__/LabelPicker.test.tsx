import {act, screen, waitFor} from '@testing-library/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {buildLabel} from '../test-utils/LabelPickerHelpers'
import {renderRelay} from '@github-ui/relay-test-utils'
import {DefaultLabelAnchor, LabelPicker, type LabelPickerProps} from '../components/LabelPicker'
import {VALUES} from '../constants/values'
import {fetchQuery} from 'react-relay'
import type {LabelPickerQuery} from '../components/__generated__/LabelPickerQuery.graphql'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import {LABELS} from '../constants/labels'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {noop} from '@github-ui/noop'
import LABEL_PICKER_CLIENT_QUERY from '../components/__generated__/LabelPickerClientQuery.graphql'
import type {LabelPickerLabel$data} from '../components/__generated__/LabelPickerLabel.graphql'
import type {ExtendedItemProps} from '../components/ItemPicker'
import {SPECIAL_VALUES} from '../constants/placeholders'
import {withDisabledCharacterKeys} from '@github-ui/ui-commands/test-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {createOperationDescriptor, Observable} from 'relay-runtime'

jest.mock('react-relay', () => ({
  ...jest.requireActual('react-relay'),
  fetchQuery: jest.fn().mockReturnValue({
    subscribe: jest.fn(),
  }),
}))

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

const catsLabel = buildLabel({name: 'lcats'})
const dogsLabel = buildLabel({name: 'ldogs'})
const mockLabels = [{node: catsLabel}, {node: dogsLabel}]

const noLabelItem: ExtendedItemProps<LabelPickerLabel$data> = {
  id: SPECIAL_VALUES.noLabelsData.id,
  description: '',
  descriptionVariant: 'inline',
  source: SPECIAL_VALUES.noLabelsData as LabelPickerLabel$data,
}

function setupEnvironment(
  {
    shortcutEnabled = true,
    labels = [],
    labelNames = [],
    showNoMatchItem = false,
    noLabelOption = undefined,
    copilotSuggestedLabels = [],
    mockValues = mockLabels,
  }: Partial<
    Pick<
      LabelPickerProps,
      'shortcutEnabled' | 'labels' | 'labelNames' | 'showNoMatchItem' | 'noLabelOption' | 'copilotSuggestedLabels'
    > & {
      mockValues?: Array<{node: LabelPickerLabel$data}>
    }
  > = {
    labels: [],
    labelNames: [],
    showNoMatchItem: false,
    noLabelOption: undefined,
    copilotSuggestedLabels: [],
  },
  totalLabelCount = labels.length,
  labelable = true,
  onSelectionChange = noop,
) {
  const environment = createMockEnvironment()

  return renderRelay<{labelPicker: LabelPickerQuery}>(
    () => (
      <LabelPicker
        repo="issues"
        owner="github"
        shortcutEnabled={shortcutEnabled}
        readonly={false}
        anchorElement={anchorProps => <DefaultLabelAnchor labels={labels} readonly={false} anchorProps={anchorProps} />}
        labels={labels}
        labelNames={labelNames}
        onSelectionChanged={onSelectionChange}
        showNoMatchItem={showNoMatchItem}
        noLabelOption={noLabelOption}
        copilotSuggestedLabels={copilotSuggestedLabels}
      />
    ),
    {
      relay: {
        queries: {
          labelPicker: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            id: 'repo-1',
            viewerIssueCreationPermissions: {
              labelable,
            },
            labels: {
              nodes: mockValues.map(n => n.node),
              totalCount: totalLabelCount || mockValues.length,
            },
            labelsByNames: {
              nodes: mockValues.filter(label => (labelNames || []).includes(label.node.name)).map(n => n.node),
            },
          }),
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )
}

const mockCommitCreateNewLabelMutation = (environment: RelayMockEnvironment, id: string, name: string) => {
  environment.mock.queueOperationResolver(operation => {
    expect(operation.fragment.node.name).toEqual('createLabelMutation')
    return MockPayloadGenerator.generate(operation, {
      Label: () => ({
        id,
        name,
        nameHTML: name,
        color: 'aaaaaa',
        description: '',
        descriptionHTML: '',
        url: '',
      }),
    })
  })
}

test('open label picker via click', async () => {
  const {user} = setupEnvironment()

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent(catsLabel.name)
  expect(options[1]).toHaveTextContent(dogsLabel.name)
})

test('open label picker via keyboard when shortcutEnabled is true', async () => {
  const {user} = setupEnvironment()

  await user.type(document.body, 'l')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent(catsLabel.name)
  expect(options[1]).toHaveTextContent(dogsLabel.name)
})

test('displays a max avmount of labels at a time (the initial load value)', async () => {
  const oldValue = VALUES.labelsInitialLoadCount
  VALUES.labelsInitialLoadCount = 1
  const {user} = setupEnvironment()

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(VALUES.labelsInitialLoadCount)
  })
  VALUES.labelsInitialLoadCount = oldValue
})

test('do not open label picker via keyboard when shortcutEnabled is false', async () => {
  await withDisabledCharacterKeys(async () => {
    const {user} = setupEnvironment()

    await user.type(document.body, 'l')

    await waitFor(() => {
      expect(screen.queryByRole('option')).toBeNull()
    })
  })
})

test('render selected labels', async () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  setupEnvironment({labels: [mockLabels[0]!.node as any]})

  const button = await screen.findByRole('button')
  expect(button).toHaveTextContent(`Label${catsLabel.name}`)
})

test('correctly renders the edit labels button', async () => {
  const {user} = setupEnvironment()

  const button = await screen.findByText('Label')
  await user.click(button)

  const editLink = await screen.findByRole('link', {name: LABELS.editLabels})
  expect(editLink).toBeInTheDocument()
  const href = editLink.getAttribute('href')

  expect(href?.endsWith('github/issues/issues/labels')).toBe(true)
})

test('shows create new option if the label is not found', async () => {
  const {user} = setupEnvironment({labels: [], showNoMatchItem: true})

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
  searchInput.focus()
  await user.paste('not found')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('Create new label: "not found"')
})

test('create new option if user chooses to create a new label', async () => {
  const {relayMockEnvironment: environment, user} = setupEnvironment({
    labels: [],
    showNoMatchItem: true,
  })

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})

  // Search for the label, and make sure the create option is visible
  await user.type(searchInput, 'new label')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })

  let options = await screen.findAllByRole('option')

  expect(options[0]).toBeDefined()
  expect(options[0]).toHaveTextContent('Create new label: "new label"')

  // Mock the create label mutation and click on the create option

  mockCommitCreateNewLabelMutation(environment, 'LA_1234', 'new label')

  if (options[0]) await user.click(options[0])

  options = await screen.findAllByRole('option')

  // Ensure the option is created and appears in the list
  expect(options[0]).toHaveTextContent('new label')
  // And that the option is selected
  expect(options[0]).toHaveAttribute('aria-selected', 'true')
})

test('ensures newly created item is selected and the id is used in the callback', async () => {
  const mock = jest.fn()
  const {relayMockEnvironment: environment, user} = setupEnvironment({showNoMatchItem: true}, 2, true, mock)

  const newLabelName = 'new label'

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})

  // Search for the label, and make sure the create option is visible
  await user.type(searchInput, 'new label')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })

  let options = await screen.findAllByRole('option')

  expect(options[0]).toBeDefined()
  expect(options[0]).toHaveTextContent(`Create new label: "${newLabelName}"`)

  mockCommitCreateNewLabelMutation(environment, 'LA_1234', newLabelName)

  if (options[0]) await user.click(options[0])

  await waitFor(async () => {
    options = await screen.findAllByRole('option')
  })

  await user.keyboard('{escape}')

  expect(mock).toHaveBeenCalledTimes(1)
  expect(mock).toHaveBeenCalledWith([
    {
      color: 'aaaaaa',
      id: 'LA_1234',
      name: newLabelName,
      nameHTML: newLabelName,
      description: '',
      url: '',
    },
  ])
})

test('ensures newly created items and other items can be selected', async () => {
  const mock = jest.fn()
  const {relayMockEnvironment: environment, user} = setupEnvironment({showNoMatchItem: true}, 2, true, mock)

  const newLabelName = 'new label'

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})

  // Search for the label, and make sure the create option is visible
  await user.type(searchInput, 'new label')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })

  let options = await screen.findAllByRole('option')

  expect(options[0]).toBeDefined()
  expect(options[0]).toHaveTextContent(`Create new label: "${newLabelName}"`)

  mockCommitCreateNewLabelMutation(environment, 'LA_1234', newLabelName)

  if (options[0]) await user.click(options[0])

  await waitFor(async () => {
    options = await screen.findAllByRole('option')
  })

  await user.clear(searchInput)
  await user.type(searchInput, 'l')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent(catsLabel.name)

  if (options[0]) await user.click(options[0])

  await user.keyboard('{escape}')

  // patch out test util fragmentType from assertion
  let mockLabel
  if (mockLabels[0]) {
    const {[' $fragmentType']: _, ...rest} = mockLabels[0].node
    mockLabel = {...rest}
  }

  expect(mock).toHaveBeenCalledTimes(1)
  expect(mock).toHaveBeenCalledWith([
    mockLabel,
    {
      color: 'aaaaaa',
      id: 'LA_1234',
      name: newLabelName,
      nameHTML: newLabelName,
      description: '',
      url: '',
    },
  ])
})

test('does not show the create new option if the label is not found and the user does not have permissions', async () => {
  const {user} = setupEnvironment({labels: [], showNoMatchItem: true}, undefined, false)
  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
  await user.type(searchInput, 'not found')

  await waitFor(() => {
    expect(screen.getByText('No labels were found')).toBeInTheDocument()
  })
})

describe('client side filtering', () => {
  test('filters labels', async () => {
    const {user} = setupEnvironment()

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
    await user.type(searchInput, 'cat')

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(1)
    })

    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('cats')
  })

  test('displays max amount of labels if filtered exceed it', async () => {
    const ogValue = VALUES.labelsInitialLoadCount
    VALUES.labelsInitialLoadCount = 1
    const {user} = setupEnvironment()

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
    await user.type(searchInput, 'l')

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(1)
    })

    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('lcats')
    VALUES.labelsInitialLoadCount = ogValue
  })

  test('filters labels when there is a no label option', async () => {
    const {user} = setupEnvironment({noLabelOption: noLabelItem})

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
    await user.type(searchInput, 'cat')

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(1)
    })

    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('cats')
  })
})

describe('server side fetching', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('uses client side filtering only if all labels are present on the client', async () => {
    const {user} = setupEnvironment()

    const button = await screen.findByText('Label')

    await user.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
    await user.type(searchInput, 'server')

    // wait for the debounce time to pass
    await act(async () => {
      await new Promise(resolve => {
        setTimeout(() => {
          resolve(true)
        }, VALUES.pickerDebounceTime)
      })
    })

    await waitFor(() => expect(fetchQuery).not.toHaveBeenCalled())
  })

  test("fetches labels from the server if we don't have all of them", async () => {
    // setup function has 2 labels by default, passing 3 for the total count on the server
    const {user} = setupEnvironment({}, 3)

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
    await user.type(searchInput, 'server')

    await waitFor(() => expect(fetchQuery).toHaveBeenCalledTimes(1))
    await waitFor(() =>
      expect(fetchQuery).toHaveBeenCalledWith(expect.anything(), expect.anything(), {
        count: VALUES.labelsPageSize,
        owner: 'github',
        query: 'server',
        repo: 'issues',
      }),
    )
  })

  test('does not query the server if labels are preloaded', async () => {
    const {user, relayMockEnvironment} = setupEnvironment({labels: []}, 3)

    // seed the store with the labels
    const operationDescriptor = createOperationDescriptor(LABEL_PICKER_CLIENT_QUERY, {
      repo: 'issues',
      owner: 'github',
    })

    const labels = ['one', 'two', 'three', 'four', 'five'].map(name => buildLabel({name}))

    const payload = {
      repository: {
        id: 'repo-1',
        labels: {
          nodes: labels,
          totalCount: 5,
        },
      },
    }

    relayMockEnvironment.commitPayload(operationDescriptor, payload)
    const button = await screen.findByText('Label')

    await user.click(button)

    expect(screen.getAllByRole('option')).toHaveLength(5)

    const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
    await user.type(searchInput, 'server')

    // wait for the debounce time to pass
    await act(async () => {
      await new Promise(resolve => {
        setTimeout(() => {
          resolve(true)
        }, VALUES.pickerDebounceTime)
      })
    })

    await waitFor(() => expect(fetchQuery).not.toHaveBeenCalled())
  })

  test('does not show create new option while loading from server', async () => {
    // only relevant with the flag enabled
    mockIsFeatureEnabled.mockImplementation(flag => flag === 'issues_react_remove_labels_loading')

    const {user} = setupEnvironment({labels: [], showNoMatchItem: true}, 3)

    const button = await screen.findByText('Label')

    await user.click(button)

    await user.paste('not found')

    await waitFor(() => {
      expect(screen.queryByText('Create new label: "not found"')).not.toBeInTheDocument()
    })
  })

  test('shows create new option when not loading', async () => {
    // only relevant with the flag enabled
    mockIsFeatureEnabled.mockImplementation(flag => flag === 'issues_react_remove_labels_loading')

    const initialCountOG = VALUES.labelsInitialLoadCount

    VALUES.labelsInitialLoadCount = 1
    const {user} = setupEnvironment({labels: [], showNoMatchItem: true}, 2)

    const button = await screen.findByText('Label')

    await user.click(button)

    await user.paste('not found')
    const mockFetch = fetchQuery as jest.Mock
    mockFetch.mockReturnValue(Observable.from({data: {repository: {labels: {nodes: [], totalCount: 0}}}}))

    expect(await screen.findByText('Create new label: "not found"')).toBeVisible()
    VALUES.labelsInitialLoadCount = initialCountOG
  })
})

describe('preselected labels', () => {
  test('passing labels as data renders the labels at the top, checked', async () => {
    const {user} = setupEnvironment({labels: [mockLabels[0]!.node as LabelPickerLabel$data]})

    const button = await screen.findByText('Label')
    await user.click(button)

    const cats = screen.queryByRole('option', {name: catsLabel.name})
    expect(cats).toBeInTheDocument()
    expect(cats).toHaveAttribute('aria-selected', 'true')
  })

  test('passing labels by names queries for them & renders the labels at the top, checked', async () => {
    const {user} = setupEnvironment({labels: [], labelNames: [catsLabel.name]})

    const button = await screen.findByText('Label')
    await user.click(button)

    const cats = await screen.findByRole('option', {name: catsLabel.name})
    expect(cats).toHaveAttribute('aria-selected', 'true')
  })

  test('prefers labelsByNames over Labels data', async () => {
    const {user} = setupEnvironment({
      labels: [mockLabels[1]!.node as LabelPickerLabel$data],
      labelNames: [catsLabel.name],
    })

    const button = await screen.findByText('Label')
    await user.click(button)

    const cats = await screen.findByRole('option', {name: catsLabel.name})
    expect(cats).toHaveAttribute('aria-selected', 'true')

    const dogs = await screen.findByRole('option', {name: dogsLabel.name})
    expect(dogs).toHaveAttribute('aria-selected', 'false')
  })
})

describe('Copilot suggested labels', () => {
  test('renders Copilot suggested labels in their own group', async () => {
    const mockOnSelectionChange = jest.fn()
    const copilotSuggestedLabel = buildLabel({name: 'copilot-suggestion'})

    const {user} = setupEnvironment(
      {
        labels: [],
        copilotSuggestedLabels: [copilotSuggestedLabel] as LabelPickerLabel$data[],
      },
      2,
      true,
      mockOnSelectionChange,
    )

    const button = await screen.findByText('Label')
    await user.click(button)

    // Verify that both the regular labels and Copilot-suggested labels are displayed
    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(3) // 2 regular + 1 copilot
    })

    // Verify that there's a group header for Copilot suggestions
    expect(screen.getByText('Copilot suggestions')).toBeInTheDocument()

    // Verify the copilot label is in the list
    const copilotOption = screen.getByRole('option', {name: copilotSuggestedLabel.name})
    expect(copilotOption).toBeInTheDocument()

    await user.click(copilotOption)

    await user.keyboard('{escape}')

    expect(mockOnSelectionChange).toHaveBeenCalledWith([copilotSuggestedLabel])
  })

  test('does not show Copilot group when no copilot labels are provided', async () => {
    const {user} = setupEnvironment()

    const button = await screen.findByText('Label')
    await user.click(button)

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(2)
    })

    expect(screen.queryByText('Copilot suggestions')).not.toBeInTheDocument()
  })

  test('can select both regular and Copilot-suggested labels', async () => {
    const mockOnSelectionChange = jest.fn()
    const copilotSuggestedLabel = buildLabel({name: 'copilot-suggestion'})

    const {user} = setupEnvironment(
      {
        labels: [],
        copilotSuggestedLabels: [copilotSuggestedLabel] as LabelPickerLabel$data[],
      },
      2,
      true,
      mockOnSelectionChange,
    )

    const button = await screen.findByText('Label')
    await user.click(button)

    // First select a regular label
    const regularOption = await screen.findByRole('option', {name: catsLabel.name})
    await user.click(regularOption)

    // Then select a Copilot-suggested label
    const copilotOption = screen.getByRole('option', {name: copilotSuggestedLabel.name})
    await user.click(copilotOption)
    await user.keyboard('{escape}')

    expect(mockOnSelectionChange).toHaveBeenCalledTimes(1)
    const selectedLabels = mockOnSelectionChange.mock.calls[0][0]
    expect(selectedLabels).toHaveLength(2)
  })
})

test('shows empty state if there are no labels', async () => {
  const {user} = setupEnvironment({
    mockValues: [],
  })

  const button = await screen.findByRole('button')
  await user.click(button)

  await waitFor(() => {
    expect(screen.getByText('No labels were found')).toBeInTheDocument()
  })
})

test('shows empty state if there are no filtered labels', async () => {
  const {user} = setupEnvironment()
  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('combobox', {name: 'Filter labels'})
  await user.type(searchInput, 'not found')

  await waitFor(() => {
    expect(screen.getByText('No labels were found')).toBeInTheDocument()
  })
})
