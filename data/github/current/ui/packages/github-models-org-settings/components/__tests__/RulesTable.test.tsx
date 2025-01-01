import {screen, within} from '@testing-library/react'
import {render as htmlRender, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
  mockResizeObserver,
  setupMatchMediaMock,
} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {RulesTable} from '../RulesTable'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('RulesTable', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run:
    mockResizeObserver()

    // Necessary to avoid a "TypeError: Cannot read properties of undefined (reading 'matches')" error:
    setupMatchMediaMock()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders when no publishers or models are allowed', () => {
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: []})

    render(<RulesTable />, {policy})

    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Enabled list'})).toBeInTheDocument()
    expect(
      screen.getByRole('heading', {name: 'View selected publishers or models navigation', level: 2}),
    ).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'View selected publishers or models'})).toBeInTheDocument()
    expect(screen.queryByRole('list', {name: 'Publisher rules'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Allowed publishers (0)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Allowed models (0)'})).toBeInTheDocument()
  })

  it('renders when no publishers or models are blocked', () => {
    const publishers = [mockPublisher({id: 1, name: 'AllowedPub'})]
    const models = [mockModel({key: 'openai/foo', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['openai/foo']})

    render(<RulesTable />, {models, policy, publishers})

    expect(screen.queryByRole('button', {name: 'Enabled list'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Disabled list'})).toBeInTheDocument()
    expect(
      screen.getByRole('heading', {name: 'View selected publishers or models navigation', level: 2}),
    ).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'View selected publishers or models'})).toBeInTheDocument()
    expect(screen.queryByRole('list', {name: 'Publisher rules'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Blocked publishers (0)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Blocked models (0)'})).toBeInTheDocument()
  })

  it('renders when some models have been allowed but no publishers', async () => {
    const orgDisplayLogin = 'my-fancy-org'
    const models = [
      mockModel({key: 'azureml/apple', registry: 'openai', name: 'apple', friendlyName: 'Apple', publisherId: 1}),
      mockModel({key: 'azureml/pear', registry: 'openai', name: 'pear', friendlyName: 'Pear', publisherId: 2}),
      mockModel({key: 'azureml/peach', registry: 'openai', name: 'peach', friendlyName: 'Peach', publisherId: 2}),
    ]
    const publishers = [mockPublisher({id: 1, name: 'Foo'}), mockPublisher({id: 2, name: 'Bar'})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: ['azureml/pear']})

    const {container, user} = render(<RulesTable />, {orgDisplayLogin, policy, models, publishers})

    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Enabled list'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Allowed publishers (0)'})).toBeInTheDocument()
    const modelsTab = screen.getByRole('button', {name: 'Allowed models (1)'})
    expect(modelsTab).toBeInTheDocument()
    expect(modelsTab).toHaveAttribute('aria-current', 'location')
    expect(within(container).queryByRole('img', {name: 'Foo logo'})).not.toBeInTheDocument()

    expect(within(container).queryByRole('link', {name: 'Apple by Foo'})).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Pear by Bar'})).toHaveAttribute(
      'href',
      '/marketplace/models/openai/pear',
    )
    expect(within(container).getByRole('img', {name: 'Bar logo'})).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Delete Bar'})).not.toBeInTheDocument()
    const blockModelButton = within(container).getByRole('button', {name: 'Delete Pear'})
    expect(blockModelButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: []}),
    })
    await user.click(blockModelButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {body: {catalog_item_keys: ['azureml/pear']}, method: 'DELETE'},
    )
  })

  it('renders when some publishers have been allowed but no models', async () => {
    const orgDisplayLogin = 'my-fancy-org'
    const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'AllowedPub'})]
    const models = [mockModel({key: 'foo/bar', publisherId: 1}), mockModel({key: 'bar/baz', publisherId: 2})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: ['bar/baz']})

    const {container, user} = render(<RulesTable />, {models, orgDisplayLogin, policy, publishers})

    expect(within(container).queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Enabled list'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'No publishers have been allowed yet.'})).not.toBeInTheDocument()
    expect(
      screen.getByRole('heading', {name: 'View selected publishers or models navigation', level: 2}),
    ).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'View selected publishers or models'})).toBeInTheDocument()
    expect(within(container).queryByRole('img', {name: 'SomePub logo'})).not.toBeInTheDocument()

    const allowedPublishersTab = within(container).getByRole('button', {name: 'Allowed publishers (1)'})
    expect(allowedPublishersTab).toBeInTheDocument()
    expect(allowedPublishersTab).toHaveAttribute('aria-current', 'location')
    expect(within(container).getByRole('list', {name: 'Publisher rules'})).toBeInTheDocument()
    expect(within(container).queryByRole('link', {name: 'SomePub 1 model'})).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'AllowedPub 1 model'})).toHaveAttribute(
      'href',
      '/marketplace?type=models&publisher=AllowedPub',
    )
    expect(within(container).queryByText('You have not allowed access to any model publisher.')).not.toBeInTheDocument()
    expect(within(container).getByRole('img', {name: 'AllowedPub logo'})).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Delete SomePub'})).not.toBeInTheDocument()
    const blockButton = within(container).getByRole('button', {name: 'Delete AllowedPub'})
    expect(blockButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({allowedModelKeys: ['foo/bar']}),
    })
    await user.click(blockButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {body: {catalog_item_keys: ['bar/baz'], models_publisher_ids: [2]}, method: 'DELETE'},
    )
  })

  it('does not render when Models is turned off for the org', () => {
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false, isAllowlist: false})

    render(<RulesTable />, {policy})

    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(
      screen.queryByRole('heading', {name: 'View selected publishers or models navigation'}),
    ).not.toBeInTheDocument()
    expect(screen.queryByRole('navigation', {name: 'View selected publishers or models'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Blocked publishers (0)'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Blocked models (0)'})).not.toBeInTheDocument()
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
