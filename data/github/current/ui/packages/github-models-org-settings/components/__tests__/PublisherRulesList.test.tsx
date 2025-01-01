import {screen} from '@testing-library/react'
import {render as htmlRender, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../../test-utils/mocks'
import {PublisherRulesList} from '../PublisherRulesList'

describe('PublisherRulesList', () => {
  it('renders when there are no allowed publishers', () => {
    const publishers = [mockPublisher({id: 1, name: 'SomePub'})]
    const models = [mockModel({key: 'foo/bar', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({allowedModelKeys: [], isAllowlist: true})

    render(<PublisherRulesList />, {models, policy, publishers})

    expect(screen.getByRole('heading', {name: /No publishers have been\s+allowed\s+yet/})).toBeInTheDocument()
  })

  it('renders when there are no blocked publishers', () => {
    const publishers = [mockPublisher({id: 1, name: 'SomePub'})]
    const models = [mockModel({key: 'foo/bar', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({allowedModelKeys: ['foo/bar'], isAllowlist: false})

    render(<PublisherRulesList />, {models, policy, publishers})

    expect(screen.getByRole('heading', {name: /No publishers have been\s+blocked\s+yet/})).toBeInTheDocument()
  })

  it('renders when there are allowed publishers', () => {
    const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'AllowedPub'})]
    const models = [
      mockModel({key: 'foo/bar', publisherId: 1}),
      mockModel({key: 'bar/baz', publisherId: 2}),
      mockModel({key: 'bleb/blob', publisherId: 2}),
    ]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: ['bar/baz', 'bleb/blob']})

    render(<PublisherRulesList />, {models, policy, publishers})

    expect(screen.queryByRole('heading', {name: /No publishers have been\s+allowed\s+yet/})).not.toBeInTheDocument()
    expect(screen.getByRole('list', {name: 'Publisher rules'})).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'AllowedPub logo'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete AllowedPub'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'SomePub logo'})).not.toBeInTheDocument()
  })

  it('renders when there are blocked publishers', () => {
    const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'BlockedPub'})]
    const models = [
      mockModel({key: 'foo/bar', publisherId: 1}),
      mockModel({key: 'bar/baz', publisherId: 2}),
      mockModel({key: 'bleb/blob', publisherId: 2}),
    ]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['foo/bar']})

    render(<PublisherRulesList />, {models, policy, publishers})

    expect(screen.queryByRole('heading', {name: /No publishers have been\s+blocked\s+yet/})).not.toBeInTheDocument()
    expect(screen.getByRole('list', {name: 'Publisher rules'})).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'BlockedPub logo'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete BlockedPub'})).toBeInTheDocument()
    expect(screen.queryByRole('img', {name: 'SomePub logo'})).not.toBeInTheDocument()
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
