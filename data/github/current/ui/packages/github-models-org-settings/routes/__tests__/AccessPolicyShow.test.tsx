import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {mockAccessPolicyShowPayload, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import {AccessPolicyShow} from '../AccessPolicyShow'

describe('AccessPolicyShow', () => {
  it('renders when Models is enabled for the organization', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true})
    const routePayload = mockAccessPolicyShowPayload({policy})

    render(<AccessPolicyShow />, {routePayload})

    expect(screen.getByRole('heading', {level: 2, name: 'Models'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Models status: Enabled'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'GitHub Privacy Statement'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Models permissions', level: 2})).toBeInTheDocument()
  })

  it('renders when Models is disabled for the organization', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false})
    const routePayload = mockAccessPolicyShowPayload({policy})

    render(<AccessPolicyShow />, {routePayload})

    expect(screen.getByRole('heading', {level: 2, name: 'Models'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'GitHub Privacy Statement'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'Models permissions', level: 2})).not.toBeInTheDocument()
  })
})
