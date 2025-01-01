import {screen} from '@testing-library/react'
import {testIdProps} from '@github-ui/test-id-props'
import {RoutingProvider, useRoutingContext} from '../RoutingProvider'
import {render} from '@github-ui/react-core/test-utils'
import {
  enterpriseRoleAssignmentsPath,
  newEnterpriseRoleAssignmentPath,
  enterpriseRolesPath,
  orgRoleAssignmentsPath,
  newOrgRoleAssignmentPath,
  stafftoolsEnterpriseRoleAssignmentsPath,
} from '@github-ui/paths'

const TestComponent = () => {
  const {roleAssignmentsPath, newRoleAssignmentPath, rolesPath} = useRoutingContext()
  return (
    <>
      <div {...testIdProps('roleAssignmentsPath')}>{roleAssignmentsPath({})}</div>
      <div {...testIdProps('newRoleAssignmentPath')}>{newRoleAssignmentPath()}</div>
      <div {...testIdProps('rolesPath')}>{rolesPath()}</div>
    </>
  )
}

describe('RoutingProvider', () => {
  it('provides correct paths for enterprise owner type', async () => {
    const slug = 'enterprise-slug'
    render(
      <RoutingProvider slug={slug} ownerType="enterprise">
        <TestComponent />
      </RoutingProvider>,
    )

    expect(screen.queryByTestId('roleAssignmentsPath')).toHaveTextContent(enterpriseRoleAssignmentsPath({slug}))
    expect(screen.queryByTestId('newRoleAssignmentPath')).toHaveTextContent(newEnterpriseRoleAssignmentPath({slug}))
    expect(screen.queryByTestId('rolesPath')).toHaveTextContent(enterpriseRolesPath({slug}))
  })

  it('provides correct paths for organization owner type', async () => {
    const slug = 'org-slug'
    render(
      <RoutingProvider slug={slug} ownerType="organization">
        <TestComponent />
      </RoutingProvider>,
    )

    expect(screen.queryByTestId('roleAssignmentsPath')).toHaveTextContent(orgRoleAssignmentsPath({slug}))
    expect(screen.queryByTestId('newRoleAssignmentPath')).toHaveTextContent(newOrgRoleAssignmentPath({slug}))
    expect(screen.queryByTestId('rolesPath')).toHaveTextContent('')
  })

  it('provides correct paths for stafftools enterprise owner type', async () => {
    const slug = 'enterprise-slug'
    render(
      <RoutingProvider slug={slug} ownerType="enterprise" stafftools>
        <TestComponent />
      </RoutingProvider>,
    )

    expect(screen.queryByTestId('roleAssignmentsPath')).toHaveTextContent(
      stafftoolsEnterpriseRoleAssignmentsPath({slug}),
    )
  })

  it('throws error when useRoutingContext is used outside of RoutingProvider', () => {
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})

    const TestComponentOutsideProvider = () => {
      useRoutingContext()
      return null
    }

    expect(() => render(<TestComponentOutsideProvider />)).toThrow(
      'useRoutingContext must be used within a RoutingProvider',
    )

    expect(consoleErrorSpy).toHaveBeenCalled()

    consoleErrorSpy.mockRestore()
  })
})
