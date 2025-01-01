import {screen} from '@testing-library/react'
import {render as htmlRender, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {mockAccessPolicyShowPayload, mockModel, mockOrganizationAccessPolicy} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {ModelsPermissions} from '../ModelsPermissions'

describe('ModelsPermissions', () => {
  it('renders when there are no restrictions', () => {
    const models = [mockModel({key: 'foo/bar', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['foo/bar']})

    render(<ModelsPermissions />, {models, policy})

    expect(screen.getByRole('group', {name: 'Select how models access should be restricted'})).toBeInTheDocument()
    const allRadio = screen.getByRole('radio', {name: 'All publishers'})
    expect(allRadio).toBeInTheDocument()
    expect(allRadio).toBeChecked()
    const selectModelsRadio = screen.getByRole('radio', {name: 'Only select models'})
    expect(selectModelsRadio).toBeInTheDocument()
    expect(selectModelsRadio).not.toBeChecked()
  })

  it('renders when there are restrictions', () => {
    const models = [mockModel({key: 'foo/bar', publisherId: 1}), mockModel({key: 'bar/baz', publisherId: 2})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['foo/bar']})

    render(<ModelsPermissions />, {models, policy})

    expect(screen.getByRole('group', {name: 'Select how models access should be restricted'})).toBeInTheDocument()
    const allRadio = screen.getByRole('radio', {name: 'All publishers'})
    expect(allRadio).toBeInTheDocument()
    expect(allRadio).not.toBeChecked()
    const selectModelsRadio = screen.getByRole('radio', {name: 'Only select models'})
    expect(selectModelsRadio).toBeInTheDocument()
    expect(selectModelsRadio).toBeChecked()
  })

  it('does not render when Models is turned off for the org', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false})

    render(<ModelsPermissions />, {policy})

    expect(screen.queryByRole('group', {name: 'Select how models access should be restricted'})).not.toBeInTheDocument()
    expect(screen.queryByRole('radio', {name: 'All publishers'})).not.toBeInTheDocument()
    expect(screen.queryByRole('radio', {name: 'Only select models'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(
    <OrganizationAccessPolicyProvider>
      <PublishersProvider>{component}</PublishersProvider>
    </OrganizationAccessPolicyProvider>,
    {wrapper: withBaseProvidersWrapper(), routePayload},
  )
}
