import {describe, it, expect, afterEach} from '@github-ui/tests'
import {userEvent, page} from '@github-ui/tests/browser'
import {vi} from 'vitest'
import {screen, within, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../../test-utils/mocks'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {RulesTable} from '../RulesTable'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
    reactFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('RulesTable', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  beforeEach(async () => {
    await page.viewport(1024, 768)
  })

  it('renders when no publishers or models are allowed', () => {
    const models = [mockModel()]
    const publishers = [mockPublisher()]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: []})

    render(<RulesTable models={models} publishers={publishers} />, {models, publishers, policy})

    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Enabled list'})).toBeInTheDocument()
    expect(
      screen.getByRole('heading', {name: 'View selected publishers or models navigation', level: 2}),
    ).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'View selected publishers or models'})).toBeInTheDocument()
    expect(screen.queryByRole('list', {name: 'Publisher rules'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Allowed publishers (0)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Allowed models (0)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Add models or publishers'})).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to allow'})).not.toBeInTheDocument()
  })

  it('renders when no publishers or models are blocked', () => {
    const publishers = [mockPublisher({id: 1, name: 'AllowedPub'})]
    const models = [mockModel({key: 'openai/foo', publisherId: 1})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['openai/foo']})

    render(<RulesTable models={models} publishers={publishers} />, {models, policy, publishers})

    expect(screen.queryByRole('button', {name: 'Enabled list'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Disabled list'})).toBeInTheDocument()
    expect(
      screen.getByRole('heading', {name: 'View selected publishers or models navigation', level: 2}),
    ).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'View selected publishers or models'})).toBeInTheDocument()
    expect(screen.queryByRole('list', {name: 'Publisher rules'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Blocked publishers (0)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Blocked models (0)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Add models or publishers'})).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to block'})).not.toBeInTheDocument()
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

    const {container} = render(<RulesTable models={models} publishers={publishers} />, {
      orgDisplayLogin,
      policy,
      models,
      publishers,
    })

    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Enabled list'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Allowed publishers (0)'})).toBeInTheDocument()
    const modelsTab = screen.getByRole('button', {name: 'Allowed models (1)'})
    expect(modelsTab).toBeInTheDocument()
    expect(modelsTab).toHaveAttribute('aria-current', 'location')
    const toggleDialogButton = within(container).getByRole('button', {name: 'Add models or publishers'})
    expect(toggleDialogButton).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to allow'})).not.toBeInTheDocument()
    expect(within(container).queryByRole('img', {name: 'Foo logo'})).not.toBeInTheDocument()

    await userEvent.click(toggleDialogButton)

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to allow'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('treeitem', {name: 'Foo'})).toBeInTheDocument()
    expect(within(dialog).getByTestId('publisher-checkbox-1')).toBeInTheDocument()
    expect(within(dialog).getByRole('treeitem', {name: 'Bar'})).toBeInTheDocument()
    expect(within(dialog).getByTestId('publisher-checkbox-2')).toBeInTheDocument()
    const closeDialogButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeDialogButton).toBeInTheDocument()

    await userEvent.click(closeDialogButton)

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
    await userEvent.click(blockModelButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {body: {model_slugs: ['azureml/pear']}, method: 'DELETE'},
    )
  })

  it('renders when some publishers have been allowed but no models', async () => {
    const orgDisplayLogin = 'my-fancy-org'
    const publishers = [mockPublisher({id: 1, name: 'SomePub'}), mockPublisher({id: 2, name: 'AllowedPub'})]
    const models = [mockModel({key: 'foo/bar', publisherId: 1}), mockModel({key: 'bar/baz', publisherId: 2})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: ['bar/baz']})

    const {container} = render(<RulesTable models={models} publishers={publishers} />, {
      models,
      orgDisplayLogin,
      policy,
      publishers,
    })

    expect(within(container).queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Enabled list'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {name: 'No publishers have been allowed yet.'})).not.toBeInTheDocument()
    expect(
      screen.getByRole('heading', {name: 'View selected publishers or models navigation', level: 2}),
    ).toBeInTheDocument()
    expect(screen.getByRole('navigation', {name: 'View selected publishers or models'})).toBeInTheDocument()
    const dialogToggleButton = within(container).getByRole('button', {name: 'Add models or publishers'})
    expect(dialogToggleButton).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to allow'})).not.toBeInTheDocument()
    expect(within(container).queryByRole('img', {name: 'SomePub logo'})).not.toBeInTheDocument()

    await userEvent.click(dialogToggleButton)

    const addPublisherModal = screen.getByRole('dialog', {name: 'Select models and publishers to allow'})
    expect(addPublisherModal).toBeInTheDocument()
    const closePublisherModalButton = within(addPublisherModal).getByRole('button', {name: 'Close'})
    expect(closePublisherModalButton).toBeInTheDocument()

    await userEvent.click(closePublisherModalButton)

    const allowedPublishersTab = within(container).getByRole('button', {name: 'Allowed publishers (1)'})
    expect(allowedPublishersTab).toBeInTheDocument()
    expect(allowedPublishersTab).toHaveAttribute('aria-current', 'location')
    expect(within(container).getByRole('list', {name: 'Publisher rules'})).toBeInTheDocument()
    expect(within(container).queryByRole('link', {name: 'SomePub 1 model'})).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'AllowedPub 1model'})).toHaveAttribute(
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
    await userEvent.click(blockButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {body: {model_slugs: ['bar/baz'], models_publisher_ids: [2]}, method: 'DELETE'},
    )
  })

  it('does not render when Models is turned off for the org', () => {
    const models = [mockModel()]
    const publishers = [mockPublisher()]
    const policy = mockOrganizationAccessPolicy({isModelsEnabled: false, isAllowlist: false})

    render(<RulesTable models={models} publishers={publishers} />, {policy, models, publishers})

    expect(screen.queryByRole('button', {name: 'Disabled list'})).not.toBeInTheDocument()
    expect(
      screen.queryByRole('heading', {name: 'View selected publishers or models navigation'}),
    ).not.toBeInTheDocument()
    expect(screen.queryByRole('navigation', {name: 'View selected publishers or models'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Blocked publishers (0)'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Blocked models (0)'})).not.toBeInTheDocument()
  })

  it('renders with a count of 0 for blocklist when there are more allowed models than models in the payload', () => {
    const models = [mockModel({key: 'openai/foo'})]
    const publishers = [mockPublisher()]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['openai/foo', 'other/thing']})

    render(<RulesTable models={models} publishers={publishers} />, {models, policy, publishers})

    expect(screen.getByRole('button', {name: 'Blocked models (0)'})).toBeInTheDocument()
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
