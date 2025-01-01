import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {EnterpriseRoleAssignments} from '../routes/EnterpriseRoleAssignments'
import {getEnterpriseRoleAssignmentsRoutePayload} from '../test-utils/mock-data'

test('Renders the EnterpriseRoleAssignments', () => {
  const routePayload = getEnterpriseRoleAssignmentsRoutePayload()
  render(<EnterpriseRoleAssignments />, {
    routePayload,
  })
  expect(screen.getByText('Enterprise roles')).toBeInTheDocument()
})
