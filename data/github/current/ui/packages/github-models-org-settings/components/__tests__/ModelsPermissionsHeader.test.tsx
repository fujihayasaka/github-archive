import {screen} from '@testing-library/react'
import {render as htmlRender, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {mockAccessPolicyShowPayload, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {ModelsPermissionsHeader} from '../ModelsPermissionsHeader'

describe('ModelsPermissionsHeader', () => {
  it('renders when Models is enabled for the org', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true})
    render(<ModelsPermissionsHeader />, {policy})
    expect(screen.getByRole('heading', {name: 'Models permissions', level: 2})).toBeInTheDocument()
  })

  it('does not render when Models is disabled for the org', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false})
    render(<ModelsPermissionsHeader />, {policy})
    expect(screen.queryByRole('heading', {name: 'Models permissions', level: 2})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(<OrganizationAccessPolicyProvider>{component}</OrganizationAccessPolicyProvider>, {
    wrapper: withBaseProvidersWrapper(),
    routePayload,
  })
}
