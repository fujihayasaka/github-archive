import {screen, waitFor} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'
import {AssigneesSection, type AssigneesSectionProps} from '../../components/AssigneesSection'
import {getAssignee, getAssigneesSectionProps} from '../../test-utils/mock-data'
import type {UpdateAlertAssigneesResponse} from '../../hooks/use-update-alert-assignees-mutation'
import type {AvailableAssigneesResponse} from '../../hooks/use-available-assignees-query'

const mockServer = setupServer()

beforeAll(() => {
  mockServer.listen({
    onUnhandledRequest: 'error',
  })
})
beforeEach(() => {
  mockServer.resetHandlers()
})
afterAll(() => {
  mockServer.close()
})

const monalisa = getAssignee()
const octocat = getAssignee({
  id: 2,
  login: 'octocat',
  name: null,
  avatarUrl: 'https://avatars.githubusercontent.com/u/2?v=4',
  profilePath: '/octocat',
})

const defaultProps = getAssigneesSectionProps({
  assignees: [],
})

const render = (props?: Partial<AssigneesSectionProps>) =>
  reactRender(<AssigneesSection {...defaultProps} {...props} />)

test('renders', () => {
  render()

  expect(screen.getByRole('button', {name: 'Edit assignees'})).toBeInTheDocument()
})

test('can assign new users', async () => {
  const patchSpy = jest.fn()

  mockServer.use(
    http.get('/monalisa/happy/security/code-scanning/available-assignees', async () => {
      return HttpResponse.json({
        users: [
          getAssignee(),
          getAssignee({
            id: 2,
            login: 'octocat',
            name: null,
          }),
          getAssignee({
            id: 5,
            login: 'octodog',
            name: null,
          }),
        ],
      } satisfies AvailableAssigneesResponse)
    }),
    http.patch('/monalisa/happy/security/code-scanning/123/assignees', async ({request}) => {
      patchSpy(await request.json())

      return HttpResponse.json({assignees: []} satisfies UpdateAlertAssigneesResponse)
    }),
  )

  const {user} = render()

  await user.click(screen.getByRole('button', {name: 'Edit assignees'}))

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  await user.click(screen.getByRole('option', {name: 'octocat'}))
  await user.click(screen.getByRole('option', {name: 'octodog'}))

  // Click outside to save
  await user.click(document.body)

  expect(patchSpy).toHaveBeenCalledTimes(1)
  expect(patchSpy).toHaveBeenCalledWith({
    assignee_ids: [2, 5],
  })
})

test('cannot assign users when the view is read-only', async () => {
  render({
    readonly: true,
  })

  expect(screen.queryByRole('button')).not.toBeInTheDocument()
  expect(screen.getByText('No one assigned')).toBeInTheDocument()
})

test('renders assignees when the view is read-only', async () => {
  render({
    readonly: true,
    assignees: [monalisa, octocat],
  })

  expect(screen.queryByRole('button')).not.toBeInTheDocument()
  expect(screen.queryByText('No one assigned')).not.toBeInTheDocument()
  expect(screen.getByText('monalisa')).toBeInTheDocument()
  expect(screen.getByText('octocat')).toBeInTheDocument()
})
