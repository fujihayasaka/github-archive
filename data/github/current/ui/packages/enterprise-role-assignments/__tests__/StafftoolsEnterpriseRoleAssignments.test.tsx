import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {StafftoolsEnterpriseRoleAssignments} from '../routes/StafftoolsEnterpriseRoleAssignments'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {SelectedTab} from '../types/selected-tab'

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: jest.fn(), showBanner: jest.fn()}
  }),
}))

beforeEach(() => {
  setupExpectedAsyncErrorHandler()
})

test('Renders StafftoolsEnterpriseRoleAssignments', () => {
  const routePayload = {
    slug: 'github-inc',
    usersCount: 0,
    teamsCount: 0,
    assignments: [],
    currentPage: 1,
    pageCount: 1,
    hasWriteAccess: false,
    selectedTab: SelectedTab.User,
  }
  render(<StafftoolsEnterpriseRoleAssignments />, {routePayload})
  expect(screen.getByText('Enterprise role assignments')).toBeInTheDocument()
})
