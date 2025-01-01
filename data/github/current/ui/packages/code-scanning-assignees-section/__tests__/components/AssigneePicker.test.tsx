import {screen, waitFor} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {getAssignee, getCodeScanningAssigneesRepository} from '../../test-utils/mock-data'
import {AssigneePicker, type AssigneePickerProps} from '../../components/AssigneePicker'
import type {AvailableAssigneesResponse} from '../../hooks/use-available-assignees-query'

const monalisa = getAssignee()
const octocat = getAssignee({
  id: 2,
  login: 'octocat',
  name: null,
  avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
  profilePath: '/octocat',
})
const copilot = getAssignee({
  id: 3789,
  login: 'Copilot',
  name: null,
  avatarUrl: 'https://avatars.githubusercontent.com/u/3789?v=4',
  profilePath: '/apps/copilot-swe-agent',
  isCopilot: true,
})
const octocats = Array.from({length: 25}, (_, i) => {
  return getAssignee({
    id: i + 3,
    login: `octocat${i + 3}`,
    name: null,
    avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
    profilePath: `/octocat${i + 3}`,
  })
})
const availableAssignees = [octocat, monalisa, copilot]

const getAvailableAssigneesSpy = jest.fn()
const mockServer = setupServer()

beforeAll(() => {
  mockServer.listen({
    onUnhandledRequest: 'error',
  })
})
beforeEach(() => {
  mockServer.resetHandlers(
    http.get('/monalisa/happy/security/code-scanning/available-assignees', async ({request}) => {
      getAvailableAssigneesSpy(Object.fromEntries(new URL(request.url, 'http://localhost').searchParams))

      const query = new URL(request.url, 'http://localhost').searchParams.get('query') ?? ''
      const filteredAssignees = availableAssignees.filter(assignee => {
        return assignee.login.toLowerCase().includes(query.toLowerCase())
      })

      return HttpResponse.json({
        users: filteredAssignees,
      } satisfies AvailableAssigneesResponse)
    }),
  )
})
afterAll(() => {
  mockServer.close()
})

const onSelectionChange = jest.fn()

afterEach(() => {
  jest.clearAllMocks()
})

const defaultProps = {
  onSelectionChange,
  shortcutsEnabled: false,
  anchorElement: (props, ref) => (
    <button {...props} ref={ref} type="button">
      Edit assignees
    </button>
  ),
  currentUser: getAssignee(),
  maximumAssignees: 10,
  repository: getCodeScanningAssigneesRepository(),
  initialSelectedAssignees: [],
  mutationError: null,
} satisfies AssigneePickerProps

const render = (props?: Partial<AssigneePickerProps>) => reactRender(<AssigneePicker {...defaultProps} {...props} />)

test('renders assignees when clicking the button anchor', async () => {
  const {user} = render()

  await user.click(screen.getByRole('button', {name: 'Edit assignees'}))

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })
  const options = await screen.findAllByRole('option')
  expect(options[0]).toHaveTextContent('monalisaMona Lisa')
  expect(options[1]).toHaveTextContent(/copilot/i)
  expect(options[2]).toHaveTextContent('octocat')

  expect(getAvailableAssigneesSpy).toHaveBeenCalledWith({
    query: '',
  })
})

test('calls endpoint when searching', async () => {
  const {user} = render()

  await user.click(screen.getByRole('button', {name: 'Edit assignees'}))

  await user.click(
    screen.getByRole('combobox', {
      name: 'Filter assignees',
    }),
  )
  await user.paste('octocat')

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(1)
  })
  const options = await screen.findAllByRole('option')
  expect(options[0]).toHaveTextContent('octocat')

  expect(getAvailableAssigneesSpy).toHaveBeenCalledTimes(2)
  expect(getAvailableAssigneesSpy).toHaveBeenCalledWith({
    query: '',
  })
  expect(getAvailableAssigneesSpy).toHaveBeenCalledWith({
    query: 'octocat',
  })
})

test('renders warning when the picker opens and there are already 10 assignees selected', async () => {
  const {user} = render({
    initialSelectedAssignees: octocats.slice(0, 10),
    maximumAssignees: 10,
  })

  await user.click(screen.getByRole('button', {name: 'Edit assignees'}))

  await waitFor(() => {
    expect(screen.getByText(/You have reached the limit/)).toBeInTheDocument()
  })
})

test('renders mutation error', async () => {
  const {user} = render({
    mutationError: new Error('500: Internal server error'),
  })

  await user.click(screen.getByRole('button', {name: 'Edit assignees'}))

  await waitFor(() => {
    expect(screen.getByText('Unable to save your selection due to server error. Try again later.')).toBeInTheDocument()
  })
})

test('renders search error', async () => {
  mockServer.resetHandlers(
    http.get('/monalisa/happy/security/code-scanning/available-assignees', async () => {
      return HttpResponse.json(
        {
          message: 'Internal server error',
        },
        {
          status: 500,
          statusText: 'Internal server error',
        },
      )
    }),
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: 'Edit assignees'}))

  await waitFor(() => {
    expect(screen.getByText('Unable to complete the search for assignees. Try again later.')).toBeInTheDocument()
  })
})
