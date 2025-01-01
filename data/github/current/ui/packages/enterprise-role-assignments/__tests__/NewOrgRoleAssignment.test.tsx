import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {NewOrgRoleAssignment} from '../routes/NewOrgRoleAssignments'
import {getNewOrgRoleAssignmentRoutePayload} from '../test-utils/org-mock-data'

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: jest.fn(), showBanner: jest.fn()}
  }),
}))

test('Renders the OrgRoleAssignments', () => {
  const routePayload = getNewOrgRoleAssignmentRoutePayload()
  render(<NewOrgRoleAssignment />, {
    routePayload,
  })

  expect(screen.getByRole('heading', {level: 2, name: 'Assign role'})).toBeInTheDocument()
  expect(screen.getByTestId('role-assignment-page')).toBeInTheDocument()
})
