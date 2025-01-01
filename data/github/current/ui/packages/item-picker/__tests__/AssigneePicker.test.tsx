import {fireEvent, screen, waitFor} from '@testing-library/react'
import {mockClientEnv} from '@github-ui/client-env/mock'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {buildAssignee} from '../test-utils/AssigneePickerHelpers'
import {noop} from '@github-ui/noop'
import type {AssigneePickerAssignee$data} from '../components/__generated__/AssigneePickerAssignee.graphql'
import {renderRelay} from '@github-ui/relay-test-utils'
import {DefaultAssigneePickerAnchor} from '../components/DefaultAssigneePickerAnchor'
import {
  AssigneePicker,
  AssigneeRepositoryPicker,
  SearchAssignableRepositoryUsers,
  SearchAssignableUsersQuery,
  type AssigneePickerProps,
  type AssigneeRepositoryPickerProps,
} from '../components/AssigneePicker'
import type {AssigneePickerSearchAssignableUsersQuery} from '../components/__generated__/AssigneePickerSearchAssignableUsersQuery.graphql'
import type {AssigneePickerSearchAssignableRepositoryUsersQuery} from '../components/__generated__/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import {MockPayloadGenerator} from 'relay-test-utils'

type TestAssigneePickerProps = Pick<
  AssigneePickerProps,
  'shortcutEnabled' | 'readonly' | 'assignees' | 'showNoMatchItem' | 'name' | 'suggestions'
> & {
  maximumAssignees?: number
}

type TestAssigneeRepositoryPickerProps = TestAssigneePickerProps &
  Pick<AssigneeRepositoryPickerProps, 'assigneeTokens'> & {
    resolverSuggestedActors?: AssigneePickerAssignee$data[]
  }

const setupAssigneeRepositoryPicker = ({
  shortcutEnabled = true,
  readonly = false,
  assignees = [],
  assigneeTokens = [],
  maximumAssignees = 10,
  showNoMatchItem = false,
  name = 'assignee',
  suggestions = [],
  resolverSuggestedActors = assigneesFromTokens,
}: TestAssigneeRepositoryPickerProps) => {
  return renderRelay<{fetchQuery: AssigneePickerSearchAssignableRepositoryUsersQuery}>(
    () => (
      <AssigneeRepositoryPicker
        readonly={readonly}
        shortcutEnabled={shortcutEnabled}
        assignees={assignees}
        assigneeTokens={assigneeTokens}
        repo="issues"
        owner="github"
        onSelectionChange={noop}
        anchorElement={anchorProps => (
          <DefaultAssigneePickerAnchor assignees={assignees} readonly={readonly} anchorProps={anchorProps} />
        )}
        maximumAssignees={maximumAssignees}
        showNoMatchItem={showNoMatchItem}
        name={name}
        suggestions={suggestions}
        includeAssignableBots
        includeAuthorableBots={false}
      />
    ),
    {
      relay: {
        queries: {
          fetchQuery: {
            type: 'preloaded',
            query: SearchAssignableRepositoryUsers,
            variables: {
              owner: 'github',
              name: 'issues',
              query: assigneeTokens.length > 0 ? null : 'loginA,loginB,loginC',
              loginNames: assigneeTokens.length > 0 ? 'loginA,loginB,loginC' : null,
              first: 3,
              capabilities: ['CAN_BE_ASSIGNED'],
            },
          },
        },
        mockResolvers: {
          Repository() {
            return {suggestedActors: {nodes: resolverSuggestedActors}}
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}

const setupAssigneeIssuePicker = ({
  shortcutEnabled = true,
  readonly = false,
  assignees = [],
  maximumAssignees = 10,
}: TestAssigneePickerProps) => {
  renderRelay<{fetchQuery: AssigneePickerSearchAssignableUsersQuery}>(
    () => (
      <AssigneePicker
        readonly={readonly}
        shortcutEnabled={shortcutEnabled}
        assignees={assignees}
        repo="issues"
        owner="github"
        number={123}
        onSelectionChange={noop}
        anchorElement={anchorProps => (
          <DefaultAssigneePickerAnchor assignees={assignees} readonly={readonly} anchorProps={anchorProps} />
        )}
        maximumAssignees={maximumAssignees ?? 10}
      />
    ),
    {
      relay: {
        queries: {
          fetchQuery: {
            type: 'preloaded',
            query: SearchAssignableUsersQuery,
            variables: {
              owner: 'github',
              name: 'issues',
              number: 123,
              query: '',
              first: 10,
            },
          },
        },
        mockResolvers: {
          Assignable() {
            return {suggestedAssignees: []}
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}

const assignees = [
  buildAssignee({login: 'login1', name: 'name1'}),
  buildAssignee({login: 'login2', name: 'name2'}),
  buildAssignee({login: 'login3', name: 'name3'}),
] as AssigneePickerAssignee$data[]

const maxAssignees = Array.from({length: 10}, (_, i) =>
  buildAssignee({login: `login${i + 1}`, name: `name${i + 1}`}),
) as AssigneePickerAssignee$data[]

const assigneesFromTokens = [
  buildAssignee({login: 'loginA', name: 'nameA'}),
  buildAssignee({login: 'loginB', name: 'nameB'}),
  buildAssignee({login: 'loginC', name: 'nameC'}),
] as AssigneePickerAssignee$data[]

describe('AssigneeRepositoryPicker', () => {
  test('render assignees when clicking the button anchor', async () => {
    setupAssigneeRepositoryPicker({assignees, assigneeTokens: [], shortcutEnabled: true, readonly: false})

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(3)
    })
    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('login1name1')
    expect(options[1]).toHaveTextContent('login2name2')
    expect(options[2]).toHaveTextContent('login3name3')
  })

  test('render picker with a different name', async () => {
    setupAssigneeRepositoryPicker({
      assignees: [],
      assigneeTokens: [],
      shortcutEnabled: true,
      readonly: false,
      name: 'author',
    })

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter authors'})

    expect(searchInput).toBeInTheDocument()
  })

  test('render no match custom item', async () => {
    const {user} = setupAssigneeRepositoryPicker({
      assignees: [],
      assigneeTokens: [],
      shortcutEnabled: true,
      readonly: false,
      showNoMatchItem: true,
    })

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    const searchInput = screen.getByRole('combobox', {name: 'Filter assignees'})
    await user.type(searchInput, 'no-match')

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(1)
    })

    const options = await screen.findAllByRole('option')

    // Item text and description
    expect(options[0]).toHaveTextContent('assignee:no-matchFilter by user')
  })

  test('do not render no match custom item', async () => {
    const {user, relayMockEnvironment} = setupAssigneeRepositoryPicker({
      assignees: [],
      assigneeTokens: [],
      shortcutEnabled: true,
      readonly: false,
      showNoMatchItem: false,
    })

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    relayMockEnvironment.mock.queueOperationResolver(operation => {
      return MockPayloadGenerator.generate(operation, {
        ActorConnection: () => ({
          nodes: [],
          totalCount: 0,
        }),
      })
    })

    const searchInput = screen.getByRole('combobox', {name: 'Filter assignees'})
    await user.type(searchInput, 'no-match')

    await waitFor(() => {
      expect(screen.getByText('No assignees were found')).toBeDefined()
    })
  })

  test('render assignees when hitting shortcut key', async () => {
    setupAssigneeRepositoryPicker({assignees, assigneeTokens: [], shortcutEnabled: true, readonly: false})
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.keyDown(document, {key: 'a'})

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(3)
    })
    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('login1name1')
    expect(options[1]).toHaveTextContent('login2name2')
    expect(options[2]).toHaveTextContent('login3name3')
  })

  test('render assignees from tokens', async () => {
    setupAssigneeRepositoryPicker({
      assignees: [],
      assigneeTokens: ['loginA', 'loginB', 'loginC'],
      shortcutEnabled: true,
      readonly: false,
    })

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(3)
    })
    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('loginAnameA')
    expect(options[1]).toHaveTextContent('loginBnameB')
    expect(options[2]).toHaveTextContent('loginCnameC')
  })

  test('render Copilot', async () => {
    mockClientEnv({
      featureFlags: ['use_copilot_avatar'],
    })
    const suggestedActors = [
      buildAssignee({login: 'testLogin', name: 'testName', isCopilot: true, typename: 'Bot'}),
    ] as AssigneePickerAssignee$data[]

    setupAssigneeRepositoryPicker({
      assignees: [],
      assigneeTokens: ['loginA', 'loginB', 'loginC'],
      shortcutEnabled: true,
      readonly: false,
      resolverSuggestedActors: suggestedActors,
    })

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(1)
    })
    const options = await screen.findAllByRole('option')

    expect(screen.getByTestId('copilot-avatar')).toBeInTheDocument()
    expect(options[0]).toHaveTextContent('CopilotYour AI pair programmer')
  })
})

describe('AssigneePicker', () => {
  test('render assignees when clicking the button anchor', async () => {
    setupAssigneeIssuePicker({assignees, shortcutEnabled: true, readonly: false})

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(4)
    })
    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('login1name1')
    expect(options[1]).toHaveTextContent('login2name2')
    expect(options[2]).toHaveTextContent('login3name3')
  })

  test('render assignees when hitting shortcut key', async () => {
    setupAssigneeIssuePicker({assignees, shortcutEnabled: true, readonly: false})
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.keyDown(document, {key: 'a'})

    await waitFor(() => {
      expect(screen.getAllByRole('option')).toHaveLength(4)
    })
    const options = await screen.findAllByRole('option')

    expect(options[0]).toHaveTextContent('login1name1')
    expect(options[1]).toHaveTextContent('login2name2')
    expect(options[2]).toHaveTextContent('login3name3')
  })

  test('renders warning when the picker opens and there are already 10 assignees selected', async () => {
    setupAssigneeIssuePicker({assignees: maxAssignees, shortcutEnabled: true, readonly: false})

    const button = await screen.findByRole('button') // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    const options = await screen.findAllByRole('option')

    for (const option of options) {
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(option)
    }

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(document.body)

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    await waitFor(() => {
      expect(screen.getByText(/You have reached the limit/)).toBeInTheDocument()
    })
  })

  test('renders warning when the assignees count increases from 9 to 10', async () => {
    setupAssigneeIssuePicker({assignees: maxAssignees, shortcutEnabled: true, readonly: false})

    const button = await screen.findByRole('button')

    // Open the picker and select the first 9 assignees
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    for (let i = 0; i < 9; i++) {
      const option = await screen.findByText(maxAssignees[i]!.login, {selector: 'span'})
      // eslint-disable-next-line testing-library/prefer-user-event
      fireEvent.click(option)
    }

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(document.body)

    // Open again and select the tenth assignee
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    const tenthOption = await screen.findByText(maxAssignees[9]!.login, {selector: 'span'})
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(tenthOption)

    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(document.body)

    // Open the picker again to check for the warning
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(button)

    await waitFor(() => {
      expect(screen.getByText(/You have reached the limit/)).toBeInTheDocument()
    })
  })
})

test('renders as a single select if there is a single user limit based on the plan', async () => {
  setupAssigneeIssuePicker({assignees, shortcutEnabled: true, readonly: false, maximumAssignees: 1})

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.keyDown(document, {key: 'a'})
  expect(screen.getByText('Assign up to 1 people to this issue')).toBeInTheDocument()

  const picker = screen.getByTestId('item-picker-root')
  expect(picker.getAttribute('aria-multiselectable')).toBe('false')
})

test('renders as a multi select if there is a multi user limit based on the plan', async () => {
  setupAssigneeIssuePicker({assignees, shortcutEnabled: true, readonly: false, maximumAssignees: 5})

  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.keyDown(document, {key: 'a'})
  expect(screen.getByText('Assign up to 5 people to this issue')).toBeInTheDocument()

  const picker = screen.getByTestId('item-picker-root')
  expect(picker.getAttribute('aria-multiselectable')).toBe('true')
})
