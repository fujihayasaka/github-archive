import {setupExpectedAsyncErrorHandler} from '@github-ui/filter/test-utils'
import {StafftoolsOrgRoleAssignments} from '../routes/StafftoolsOrgRoleAssignments'
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

test('Renders StafftoolsOrgRoleAssignments', () => {
  const routePayload = {
    slug: 'github',
    usersCount: 0,
    teamsCount: 0,
    assignments: [],
    currentPage: 1,
    pageCount: 1,
    selectedTab: SelectedTab.User,
  }
  render(<StafftoolsOrgRoleAssignments />, {routePayload})
  expect(screen.getByText('Organization role assignments')).toBeInTheDocument()
})
