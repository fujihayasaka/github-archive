import {describe, it, expect} from '@github-ui/tests'
import {screen, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../../test-utils/mocks'
import {ModelRulesList} from '../ModelRulesList'

describe('ModelRulesList', () => {
  it('renders when there are no allowed models', () => {
    const models = [mockModel({key: 'foo/bar', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({allowedModelKeys: [], isAllowlist: true})

    render(<ModelRulesList models={models} />, {models, policy})

    expect(screen.getByRole('heading', {name: /No models have been\s+allowed\s+yet/})).toBeInTheDocument()
  })

  it('renders when there are no blocked models', () => {
    const models = [mockModel({key: 'foo/bar', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({allowedModelKeys: ['foo/bar'], isAllowlist: false})

    render(<ModelRulesList models={models} />, {models, policy})

    expect(screen.getByRole('heading', {name: /No models have been\s+blocked\s+yet/})).toBeInTheDocument()
  })

  it('renders when there are allowed models', () => {
    const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'AllowedPub'})]
    const models = [
      mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'}),
      mockModel({key: 'bar/baz', publisherId: 2, friendlyName: 'BarBaz'}),
      mockModel({key: 'bleb/blob', publisherId: 2, friendlyName: 'BlebBlob'}),
    ]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: ['bar/baz', 'bleb/blob']})

    render(<ModelRulesList models={models} />, {models, policy, publishers})

    expect(screen.queryByRole('heading', {name: /No models have been\s+allowed\s+yet/})).not.toBeInTheDocument()
    expect(screen.getByRole('list', {name: 'Model rules'})).toBeInTheDocument()
    expect(screen.getAllByRole('img', {name: 'AllowedPub logo'})).toHaveLength(2)
    expect(screen.queryByRole('button', {name: 'Delete FooBar'})).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'BarBaz by AllowedPub'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'BlebBlob by AllowedPub'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete BarBaz'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete BlebBlob'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'SomePub logo'})).not.toBeInTheDocument()
  })

  it('renders when there are blocked models', () => {
    const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'BlockedPub'})]
    const models = [
      mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'}),
      mockModel({key: 'bar/baz', publisherId: 2, friendlyName: 'BarBaz'}),
      mockModel({key: 'bleb/blob', publisherId: 2, friendlyName: 'BlebBlob'}),
    ]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['foo/bar']})

    render(<ModelRulesList models={models} />, {models, policy, publishers})

    expect(screen.queryByRole('heading', {name: /No models have been\s+blocked\s+yet/})).not.toBeInTheDocument()
    expect(screen.getByRole('list', {name: 'Model rules'})).toBeInTheDocument()
    expect(screen.getAllByRole('img', {name: 'BlockedPub logo'})).toHaveLength(2)
    expect(screen.getByRole('link', {name: 'BarBaz by BlockedPub'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'BlebBlob by BlockedPub'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete BarBaz'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete BlebBlob'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'SomePub logo'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(
    <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
      <PublishersProvider models={routePayload.models} publishers={routePayload.publishers}>
        {component}
      </PublishersProvider>
    </OrganizationAccessPolicyProvider>,
    {wrapper: withBaseProvidersWrapper()},
  )
}
