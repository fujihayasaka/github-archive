import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import type {CloseAlertOverlayProps} from '../../components/CloseAlertOverlay'
import {CloseAlertOverlay} from '../../components/CloseAlertOverlay'
import type {CloseAlertsResponse} from '../../hooks/use-close-alerts-mutation'
import {createRepository} from '@github-ui/security-campaigns-shared/test-utils/mock-data'

const setOpen = jest.fn()

const originalWindowLocation = window.location
const mockReload = jest.fn()

beforeAll(() => {
  Object.defineProperty(window, 'location', {
    configurable: true,
    value: {reload: mockReload},
  })
})

afterAll(() => {
  Object.defineProperty(window, 'location', {configurable: true, value: originalWindowLocation})
})

afterEach(() => {
  jest.clearAllMocks()
})

function getDefaultProps(): CloseAlertOverlayProps {
  return {
    setOpen,
    alertNumbers: [1],
    repository: createRepository(),
    securityCampaignNumber: 5,
    delegatedAlertDismissalEnabled: false,
  }
}

const render = (props?: Partial<CloseAlertOverlayProps>) =>
  reactRender(<CloseAlertOverlay {...getDefaultProps()} {...props} />)

it('shows overlay with all closing reasons and dismissal comment empty', async () => {
  render()

  expect(screen.getByLabelText('False positive')).toBeInTheDocument()
  expect(screen.getByLabelText('False positive')).not.toBeChecked()

  expect(screen.getByLabelText('Used in tests')).toBeInTheDocument()
  expect(screen.getByLabelText('Used in tests')).not.toBeChecked()

  expect(screen.getByLabelText("Won't fix")).toBeInTheDocument()
  expect(screen.getByLabelText("Won't fix")).not.toBeChecked()

  expect(screen.getByLabelText('Comment')).toBeInTheDocument()
  expect(screen.getByLabelText('Comment')).toHaveValue('')
})

it('shows a disabled submit button when no closing reason is selected', async () => {
  render()

  expect(screen.getByRole('button', {name: /Close alert/})).toBeDisabled()
})

it('shows a disabled submit button when a closing reason is selected, but dismissal comment is empty and delegatedAlertDismissalEnabled is enabled', async () => {
  const {user} = render({delegatedAlertDismissalEnabled: true})

  await user.click(screen.getByLabelText('False positive'))

  expect(screen.getByLabelText('Comment*')).toBeInTheDocument()
  expect(screen.getByLabelText('Comment*')).toHaveValue('')
  expect(screen.getByRole('button', {name: /Close alert/})).toBeDisabled()
})

it('shows an enabled submit button when a closing reason is selected, but dismissal comment is empty', async () => {
  const {user} = render({delegatedAlertDismissalEnabled: false})

  await user.click(screen.getByLabelText('False positive'))

  expect(screen.getByRole('button', {name: /Close alert/})).toBeEnabled()
})

it('shows a disabled submit button when a closing reason is selected, but dismissal comment is not empty', async () => {
  const {user} = render()

  await user.click(screen.getByLabelText('False positive'))
  await user.type(screen.getByLabelText('Comment'), 'test')

  expect(screen.getByRole('button', {name: /Close alert/})).not.toBeDisabled()
})

it('closes the overlay when the form is cancelled', async () => {
  const {user} = render()

  await user.click(screen.getByText('Cancel'))

  expect(setOpen).toHaveBeenCalledWith(false)
})

it('calls useNavigate when dismissal is successful', async () => {
  const {user} = render()

  const route = mockFetch.mockRoute(
    '/github/security-campaigns/security/campaigns/5/alerts',
    {
      message: 'Alerts closed successfully',
    } satisfies CloseAlertsResponse,
    {
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(screen.getByLabelText('False positive'))
  await user.type(screen.getByLabelText('Comment'), 'test')
  await user.click(screen.getByRole('button', {name: /Close alert/}))

  expect(route).toHaveBeenCalledWith(
    expect.any(String),
    expect.objectContaining({
      body: JSON.stringify({
        alert_numbers: [1],
        resolution: 'false_positive',
        dismissal_comment: 'test',
      }),
    }),
  )

  expect(setOpen).toHaveBeenCalledWith(false)
  expect(mockReload).toHaveBeenCalled()
})

it('shows an error when dismissal fails', async () => {
  const {user} = render()

  const route = mockFetch.mockRoute(
    '/github/security-campaigns/security/campaigns/5/alerts',
    {
      message: 'This is a test error message',
    } satisfies CloseAlertsResponse,
    {
      ok: false,
      status: 400,
      headers: new Headers({
        'Content-Type': 'application/json',
      }),
    },
  )

  await user.click(screen.getByLabelText('False positive'))
  await user.type(screen.getByLabelText('Comment'), 'test')
  await user.click(screen.getByRole('button', {name: /Close alert/}))

  expect(route).toHaveBeenCalled()
  expect(mockReload).not.toHaveBeenCalled()
  expect(screen.getByText('This is a test error message')).toBeInTheDocument()
})
