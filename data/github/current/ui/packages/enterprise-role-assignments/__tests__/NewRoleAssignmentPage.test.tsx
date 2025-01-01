import {act, screen, waitFor} from '@testing-library/react'
import {mockFetch} from '@github-ui/mock-fetch'
import {render} from '@github-ui/react-core/test-utils'
import {getNewRoleAssignmentPageProps, selectAndSubmitRoleAssignment} from '../test-utils/mock-data'
import {NewRoleAssignmentPage} from '../components/NewRoleAssignmentPage'

const showBannerMock = jest.fn()
const navigateMock = jest.fn()

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: navigateMock, showBanner: showBannerMock}
  }),
}))

beforeEach(() => {
  navigateMock.mockClear()
})

test('Renders RoleAssignmentPage', () => {
  const props = getNewRoleAssignmentPageProps()
  render(<NewRoleAssignmentPage {...props} />)

  const assigneeHeading = screen.getByRole('heading', {level: 3, name: 'Assign role to'})
  expect(assigneeHeading).toBeInTheDocument()
  const roleHeading = screen.getByRole('heading', {level: 3, name: 'Select role'})
  expect(roleHeading).toBeInTheDocument()
  const roleList = screen.getByTestId('role-assignment-list')
  expect(roleList).toBeInTheDocument()
  const submitButton = screen.getByRole('button', {name: 'Assign role'})
  expect(submitButton).toBeInTheDocument()
})

test('Does not submit incomplete selections', async () => {
  const props = getNewRoleAssignmentPageProps()
  const {user} = render(<NewRoleAssignmentPage {...props} />)

  const verifiedFetchFn = jest.fn()
  jest.mock('@github-ui/verified-fetch', () => {
    return {
      verifiedFetchJSON: () => verifiedFetchFn,
    }
  })

  // no assignee selected
  const roleItem = screen.getByTestId('role-assignment-list-item-audit_log_readonly')
  expect(roleItem).toBeInTheDocument()
  await user.click(roleItem)
  const submitButton = screen.getByRole('button', {name: 'Assign role'})
  expect(submitButton).toBeInTheDocument()
  await user.click(submitButton)

  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'Please select an actor and role to assign.',
    variant: 'warning',
  })
  expect(verifiedFetchFn).not.toHaveBeenCalled()
})

test('Submits to provided submit endpoint and handles successful response w/ redirect', async () => {
  const props = getNewRoleAssignmentPageProps()
  const {user} = render(<NewRoleAssignmentPage {...props} />)

  await selectAndSubmitRoleAssignment(user)

  await waitFor(async () => {
    const mockSuccessResponse = {success: true, redirect_url: 'test.com', message: 'role assignment successful'}
    await act(() => mockFetch.resolvePendingRequest(props.submitAssignmentRoute, mockSuccessResponse))

    expect(navigateMock).toHaveBeenCalledWith(mockSuccessResponse.redirect_url, undefined, {
      message: mockSuccessResponse.message,
      variant: 'success',
    })
  })
})

test('Handles failed submit w/ call to props.displayMessage', async () => {
  const props = getNewRoleAssignmentPageProps()
  const {user} = render(<NewRoleAssignmentPage {...props} />)

  await selectAndSubmitRoleAssignment(user)

  await waitFor(async () => {
    const mockErrorResponse = {success: false, error: 'this is an error message'}
    await act(() => mockFetch.resolvePendingRequest(props.submitAssignmentRoute, mockErrorResponse))

    expect(showBannerMock).toHaveBeenCalledWith({
      message: mockErrorResponse.error,
      variant: 'critical',
    })
  })
})
