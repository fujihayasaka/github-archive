import {describe, it, expect} from '@github-ui/tests'
import {render as htmlRender} from '@github-ui/react-core/future/test-utils/render'
import {screen, waitFor} from '@testing-library/react'

import {mockAccessPolicyShowPayload, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import {app} from '../../github-models-org-settings'
import type {AccessPolicyShowPayload} from '../../types'
import {accessPolicyShow} from '../access-policy-show-route'

describe('AccessPolicyShow', () => {
  it('renders when Models is enabled for the organization', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAccessConfigurable: true})
    const routePayload = mockAccessPolicyShowPayload({policy})

    await render(routePayload)

    expect(screen.getByRole('heading', {level: 2, name: 'Models'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Models status:Enabled'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'GitHub Pre-release terms'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Models permissions', level: 2})).toBeInTheDocument()
  })

  it('renders when Models is disabled for the organization', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false, isAccessConfigurable: true})
    const routePayload = mockAccessPolicyShowPayload({policy})

    await render(routePayload)

    expect(screen.getByRole('heading', {level: 2, name: 'Models'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 3, name: 'Models in your organization'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Learn more about Models.'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'GitHub Pre-release terms'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'Models permissions', level: 2})).not.toBeInTheDocument()
  })

  it('shows a message when access is not configurable by the organization', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false, isAccessConfigurable: false})
    const routePayload = mockAccessPolicyShowPayload({policy})

    await render(routePayload)

    expect(
      screen.getByText('This setting has been disabled by your enterprise policy administrators.'),
    ).toBeInTheDocument()
  })

  it('does not render the input when Models is enabled but access is not configurable', async () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: true, isAccessConfigurable: false})
    const routePayload = mockAccessPolicyShowPayload({policy})

    await render(routePayload)

    expect(screen.queryByRole('button', {name: 'Models status:Enabled'})).not.toBeInTheDocument()
    expect(
      screen.getByText('This setting has been disabled by your enterprise policy administrators.'),
    ).toBeInTheDocument()
  })
})

async function render(mainQuery: AccessPolicyShowPayload) {
  // eslint-disable-next-line testing-library/render-result-naming-convention
  const returns = htmlRender(app, accessPolicyShow.generatePath({org: mainQuery.orgDisplayLogin}), {
    embeddedData: {
      payload: {[accessPolicyShow.id]: mainQuery},
    },
  })

  await waitFor(() => {
    // eslint-disable-next-line testing-library/no-node-access
    expect(returns.baseElement.querySelectorAll('[data-hpc]').length).toBeGreaterThanOrEqual(1)
  })

  return returns
}
