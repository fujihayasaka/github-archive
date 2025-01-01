import {screen, waitFor} from '@testing-library/react'
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
import type {LabelPickerLabel$data} from '../components/__generated__/LabelPickerLabel.graphql'
import type {ExtendedItemProps} from '../components/ItemPicker'
import {SPECIAL_VALUES} from '../constants/placeholders'
import {withDisabledCharacterKeys} from '@github-ui/ui-commands/test-utils'

jest.mock('react-relay', () => ({
  ...jest.requireActual('react-relay'),
  fetchQuery: jest.fn().mockReturnValue({
    subscribe: jest.fn(),
  }),
}))

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
  }: Partial<
    Pick<LabelPickerProps, 'shortcutEnabled' | 'labels' | 'labelNames' | 'showNoMatchItem' | 'noLabelOption'>
  > = {
    labels: [],
    labelNames: [],
    showNoMatchItem: false,
    noLabelOption: undefined,
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
            id: 'issue-1',
            viewerIssueCreationPermissions: {
              labelable,
            },
            labels: {
              nodes: mockLabels.map(n => n.node),
              totalCount: totalLabelCount,
            },
            labelsByNames: {
              nodes: mockLabels.filter(label => (labelNames || []).includes(label.node.name)).map(n => n.node),
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

  const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})
  await user.type(searchInput, 'not found')

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

  const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})

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

  await waitFor(async () => {
    options = await screen.findAllByRole('option')
  })

  // Ensure the option is created and appears in the list
  expect(options[0]).toHaveTextContent('new label')
  // And that the option is selected
  expect(options[0]).toHaveAttribute('aria-selected', 'true')
})

test('ensures newly created item is selected and the id is used in the callback', async () => {
  const mock = jest.fn()
  const {relayMockEnvironment: environment, user} = setupEnvironment(
    {labels: [], showNoMatchItem: true},
    mockLabels.length,
    true,
    mock,
  )

  const newLabelName = 'new label'

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})

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
  const {relayMockEnvironment: environment, user} = setupEnvironment(
    {showNoMatchItem: true},
    mockLabels.length,
    true,
    mock,
  )

  const newLabelName = 'new label'

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})

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

  expect(mock).toHaveBeenCalledTimes(1)
  expect(mock).toHaveBeenCalledWith([
    {...mockLabels[0]?.node, url: '<mock-value-for-field-"url">'},
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
  const {user} = setupEnvironment({labels: [], showNoMatchItem: true}, mockLabels.length, false)

  const button = await screen.findByText('Label')

  await user.click(button)

  const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})
  await user.type(searchInput, 'not found')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('No matches')
})

describe('client side filtering', () => {
  test('filters labels', async () => {
    const {user} = setupEnvironment()

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})
    await user.type(searchInput, 'cat')

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(1)
    })

    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('cats')
  })

  test('filters labels when there is a no label option', async () => {
    const {user} = setupEnvironment({noLabelOption: noLabelItem})

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})
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

  test('uses client side filtering only for repo with <100 label', async () => {
    const {user} = setupEnvironment()

    const button = await screen.findByText('Label')

    await user.click(button)

    const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})
    await user.type(searchInput, 'server')

    await waitFor(() => expect(fetchQuery).not.toHaveBeenCalled())
  })

  test('uses server side filtering for repos with > 100 labels', async () => {
    const initialCountOG = VALUES.labelsInitialLoadCount

    VALUES.labelsInitialLoadCount = 1

    const {user} = setupEnvironment({labels: []}, 2)

    const button = await screen.findByText('Label')
    await user.click(button)

    const searchInput = screen.getByRole('textbox', {name: 'Filter labels'})
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
