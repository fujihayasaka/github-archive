import {render} from '@github-ui/react-core/test-utils'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {screen} from '@testing-library/react'
import {RoleDetailsRowRemoveDialog} from '../../components/RoleDetailsRowRemoveDialog'
import {getRoleDetailsRowRemoveDialogProps} from '../../test-utils/mock-data'

const showBannerMock = jest.fn()
const navigateMock = jest.fn()

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: navigateMock, showBanner: showBannerMock}
  }),
}))

jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const mockVerifiedFetch = verifiedFetchJSON as jest.Mock

interface MockResponseOptions {
  response?: {
    success: boolean
    message?: string
    error?: string
  }
  status?: number
}
// Helper to set the response - can be called at the beginning of each test
const mockFetchResponse = (options: MockResponseOptions = {}) => {
  const {response = {success: true}, status = 200} = options

  mockVerifiedFetch.mockImplementation((_path, _init) =>
    Promise.resolve({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(response),
    }),
  )
}

beforeEach(() => {
  jest.clearAllMocks()
})

test('Renders text, cancel, remove', () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  render(<RoleDetailsRowRemoveDialog {...props} />)

  expect(screen.getByText('about to remove the assignment', {exact: false})).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Remove'})).toBeInTheDocument()
})

test('Cancel button closes modal without submitting', async () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RoleDetailsRowRemoveDialog {...props} />)

  const cancel = screen.queryByRole('button', {name: 'Cancel'})
  expect(cancel).toBeInTheDocument()
  await user.click(cancel!)

  expect(props.setOpen).toHaveBeenCalledWith(false)
})

test('Remove button submits and reloads page with banner', async () => {
  mockFetchResponse({
    response: {
      success: true,
      message: 'Success message',
    },
  })

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RoleDetailsRowRemoveDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalled()
  expect(navigateMock).toHaveBeenCalledWith(
    window.location.pathname,
    {replace: true},
    {
      message: 'Success message',
      variant: 'success',
    },
  )
})

test('Remove failure shows banner with server message when status is 422', async () => {
  mockFetchResponse({response: {success: false, error: 'error message'}, status: 422})

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RoleDetailsRowRemoveDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'error message',
    variant: 'critical',
  })
})

test('Remove failure shows banner with server message when status is 403', async () => {
  mockFetchResponse({response: {success: false, error: 'error message'}, status: 403})

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RoleDetailsRowRemoveDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'error message',
    variant: 'critical',
  })
})

test('Remove failure shows generic error message', async () => {
  mockFetchResponse({status: 500})

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RoleDetailsRowRemoveDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'Something went wrong while removing the role assignment. Please try again later.',
    variant: 'critical',
  })
})
