import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getNewEnterpriseRoleAssignmentRoutePayload} from '../test-utils/mock-data'
import {NewEnterpriseRoleAssignment} from '../routes/NewEnterpriseRoleAssignment'

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: jest.fn(), showBanner: jest.fn()}
  }),
}))

test('Renders NewEnterpriseRoleAssignment', () => {
  const routePayload = getNewEnterpriseRoleAssignmentRoutePayload()
  render(<NewEnterpriseRoleAssignment />, {
    routePayload,
  })

  const heading = screen.getByRole('heading', {level: 1, name: 'Assign role'})
  expect(heading).toBeInTheDocument()
  const rolePage = screen.getByTestId('role-assignment-page')
  expect(rolePage).toBeInTheDocument()
})
