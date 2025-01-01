import {describe, it, expect, afterEach} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {vi} from 'vitest'
import {screen, within, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import type {AccessPolicyShowPayload} from '../../types'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {SelectionProvider} from '../../contexts/SelectionContext'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../../test-utils/mocks'
import {AddRuleDialog} from '../AddRuleDialog'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
    reactFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('AddRuleDialog', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  it('renders for an allow list', async () => {
    const availablePublisher = mockPublisher({id: 1, name: 'Available Publisher', totalModels: 1})
    const allowedPublisher = mockPublisher({id: 2, name: 'Allowed Publisher', totalModels: 1})
    const models = [mockModel({key: 'foo/bar', publisherId: 1}), mockModel({key: 'bar/baz', publisherId: 2})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: ['bar/baz']})
    const publishers = [allowedPublisher, availablePublisher]

    render(<AddRuleDialog models={models} publishers={publishers} />, {
      models,
      policy,
      publishers,
    })

    const dialogToggleButton = screen.getByRole('button', {name: 'Add models or publishers'})
    expect(dialogToggleButton).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to allow'})).not.toBeInTheDocument()

    await userEvent.click(dialogToggleButton)

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to allow'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('tree', {name: 'Select models and publishers'})).toBeInTheDocument()
    expect(within(dialog).getByRole('treeitem', {name: 'Available Publisher'})).toBeInTheDocument()
    expect(within(dialog).getByRole('treeitem', {name: 'Allowed Publisher'})).toBeInTheDocument()
    expect(
      within(dialog).getByRole('heading', {name: 'Select models and publishers to allow', level: 1}),
    ).toBeInTheDocument()
    expect(within(dialog).getByRole('group', {name: 'Models from Allowed Publisher'})).toBeInTheDocument()
    expect(within(dialog).getByTestId(`publisher-checkbox-${availablePublisher.id}`)).not.toBeChecked()
    expect(within(dialog).getByTestId(`publisher-checkbox-${allowedPublisher.id}`)).toBeChecked()
    expect(within(dialog).getByRole('button', {name: 'Update enabled list'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()

    await userEvent.click(closeButton)

    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to allow'})).not.toBeInTheDocument()
  })

  it('renders for a block list', async () => {
    const availablePublisher = mockPublisher({id: 1, name: 'Available Publisher', totalModels: 1})
    const blockedPublisher = mockPublisher({id: 2, name: 'Blocked Publisher', totalModels: 1})
    const models = [mockModel({key: 'foo/bar', publisherId: 1}), mockModel({key: 'bar/baz', publisherId: 2})]
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: ['foo/bar']})
    const publishers = [blockedPublisher, availablePublisher]

    render(<AddRuleDialog models={models} publishers={publishers} />, {
      models,
      policy,
      publishers,
    })

    const dialogToggleButton = screen.getByRole('button', {name: 'Add models or publishers'})
    expect(dialogToggleButton).toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to block'})).not.toBeInTheDocument()

    await userEvent.click(dialogToggleButton)

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to block'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('tree', {name: 'Select models and publishers'})).toBeInTheDocument()
    expect(within(dialog).getByRole('treeitem', {name: 'Available Publisher'})).toBeInTheDocument()
    expect(within(dialog).getByRole('treeitem', {name: 'Blocked Publisher'})).toBeInTheDocument()
    expect(within(dialog).getByRole('img', {name: 'Available Publisher logo'})).toBeInTheDocument()
    expect(within(dialog).getByRole('img', {name: 'Blocked Publisher logo'})).toBeInTheDocument()
    expect(
      within(dialog).getByRole('heading', {name: 'Select models and publishers to block', level: 1}),
    ).toBeInTheDocument()
    expect(within(dialog).getByRole('group', {name: 'Models from Blocked Publisher'})).toBeInTheDocument()
    expect(within(dialog).getByTestId(`publisher-checkbox-${availablePublisher.id}`)).not.toBeChecked()
    expect(within(dialog).getByTestId(`publisher-checkbox-${blockedPublisher.id}`)).toBeChecked()
    expect(within(dialog).getByRole('button', {name: 'Update disabled list'})).toBeInTheDocument()
    const closeButton = within(dialog).getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()

    await userEvent.click(closeButton)

    expect(screen.queryByRole('dialog', {name: 'Select models and publishers to block'})).not.toBeInTheDocument()
  })

  it('does not block a publisher who still has some models allowed after deselecting some', async () => {
    const orgDisplayLogin = 'someNiceOrg'
    const publisher = mockPublisher({totalModels: 2})
    const model1 = mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'})
    const model2 = mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'BarBaz'})
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: [model1.key, model2.key]})
    const models = [model1, model2]
    const publishers = [publisher]

    render(<AddRuleDialog models={models} publishers={publishers} />, {
      models,
      orgDisplayLogin,
      policy,
      publishers,
    })

    await userEvent.click(screen.getByRole('button', {name: 'Add models or publishers'}))

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to allow'})
    expect(dialog).toBeInTheDocument()

    const publisherTreeItem = within(dialog).getByRole('treeitem', {name: publisher.name})
    expect(publisherTreeItem).toBeInTheDocument()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).toBeChecked()

    // Expand publisher sub-tree that includes its models:
    publisherTreeItem.focus()
    await userEvent.keyboard('[ArrowRight]')

    const modelsGroup = screen.getByRole('group', {name: `Models from ${publisher.name}`})
    expect(modelsGroup).toBeInTheDocument()
    expect(within(modelsGroup).getByRole('checkbox', {name: `Select ${model1.friendlyName}`})).toBeChecked()
    const model2Checkbox = within(modelsGroup).getByRole('checkbox', {name: `Select ${model2.friendlyName}`})
    expect(model2Checkbox).toBeChecked()

    await userEvent.click(model2Checkbox)

    expect(model2Checkbox).not.toBeChecked()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).toBePartiallyChecked()
    const submitButton = within(dialog).getByRole('button', {name: 'Update enabled list'})
    expect(submitButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: [model1.key]}),
    })
    await userEvent.click(submitButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {model_slugs: [model2.key]}},
    )
  })

  it('does not block a publisher who still has some models allowed after selecting some', async () => {
    const orgDisplayLogin = 'someNiceOrg'
    const publisher = mockPublisher({totalModels: 2})
    const model1 = mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'})
    const model2 = mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'BarBaz'})
    const policy = mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: []})
    const models = [model1, model2]
    const publishers = [publisher]

    render(<AddRuleDialog models={models} publishers={publishers} />, {
      models,
      orgDisplayLogin,
      policy,
      publishers,
    })

    await userEvent.click(screen.getByRole('button', {name: 'Add models or publishers'}))

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to allow'})
    expect(dialog).toBeInTheDocument()

    const publisherTreeItem = within(dialog).getByRole('treeitem', {name: publisher.name})
    expect(publisherTreeItem).toBeInTheDocument()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).not.toBeChecked()

    // Expand publisher sub-tree that includes its models:
    publisherTreeItem.focus()
    await userEvent.keyboard('[ArrowRight]')

    const modelsGroup = screen.getByRole('group', {name: `Models from ${publisher.name}`})
    expect(modelsGroup).toBeInTheDocument()
    expect(within(modelsGroup).getByRole('checkbox', {name: `Select ${model1.friendlyName}`})).not.toBeChecked()
    const model2Checkbox = within(modelsGroup).getByRole('checkbox', {name: `Select ${model2.friendlyName}`})
    expect(model2Checkbox).not.toBeChecked()

    await userEvent.click(model2Checkbox)

    expect(model2Checkbox).toBeChecked()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).toBePartiallyChecked()
    const submitButton = within(dialog).getByRole('button', {name: 'Update enabled list'})
    expect(submitButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: true, allowedModelKeys: [model2.key]}),
    })
    await userEvent.click(submitButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {model_slugs: [model2.key]}},
    )
  })

  it('does not allow a publisher who still has some models blocked after deselecting some', async () => {
    const orgDisplayLogin = 'someNiceOrg'
    const publisher = mockPublisher({totalModels: 2})
    const model1 = mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'})
    const model2 = mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'BarBaz'})
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: []})
    const models = [model1, model2]
    const publishers = [publisher]

    render(<AddRuleDialog models={models} publishers={publishers} />, {
      models,
      orgDisplayLogin,
      policy,
      publishers,
    })

    await userEvent.click(screen.getByRole('button', {name: 'Add models or publishers'}))

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to block'})
    expect(dialog).toBeInTheDocument()

    const publisherTreeItem = within(dialog).getByRole('treeitem', {name: publisher.name})
    expect(publisherTreeItem).toBeInTheDocument()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).toBeChecked()

    // Expand publisher sub-tree that includes its models:
    publisherTreeItem.focus()
    await userEvent.keyboard('[ArrowRight]')

    const modelsGroup = screen.getByRole('group', {name: `Models from ${publisher.name}`})
    expect(modelsGroup).toBeInTheDocument()
    expect(within(modelsGroup).getByRole('checkbox', {name: `Select ${model1.friendlyName}`})).toBeChecked()
    const model2Checkbox = within(modelsGroup).getByRole('checkbox', {name: `Select ${model2.friendlyName}`})
    expect(model2Checkbox).toBeChecked()

    await userEvent.click(model2Checkbox)

    expect(model2Checkbox).not.toBeChecked()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).toBePartiallyChecked()
    const submitButton = within(dialog).getByRole('button', {name: 'Update disabled list'})
    expect(submitButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: [model2.key]}),
    })
    await userEvent.click(submitButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'POST', body: {model_slugs: [model2.key]}},
    )
  })

  it('does not allow a publisher who still has some models blocked after selecting some', async () => {
    const orgDisplayLogin = 'someNiceOrg'
    const publisher = mockPublisher({totalModels: 2})
    const model1 = mockModel({key: 'foo/bar', publisherId: 1, friendlyName: 'FooBar'})
    const model2 = mockModel({key: 'bar/baz', publisherId: 1, friendlyName: 'BarBaz'})
    const policy = mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: [model1.key, model2.key]})
    const models = [model1, model2]
    const publishers = [publisher]

    render(<AddRuleDialog models={models} publishers={publishers} />, {
      models,
      orgDisplayLogin,
      policy,
      publishers,
    })

    await userEvent.click(screen.getByRole('button', {name: 'Add models or publishers'}))

    const dialog = screen.getByRole('dialog', {name: 'Select models and publishers to block'})
    expect(dialog).toBeInTheDocument()

    const publisherTreeItem = within(dialog).getByRole('treeitem', {name: publisher.name})
    expect(publisherTreeItem).toBeInTheDocument()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).not.toBeChecked()

    // Expand publisher sub-tree that includes its models:
    publisherTreeItem.focus()
    await userEvent.keyboard('[ArrowRight]')

    const modelsGroup = screen.getByRole('group', {name: `Models from ${publisher.name}`})
    expect(modelsGroup).toBeInTheDocument()
    expect(within(modelsGroup).getByRole('checkbox', {name: `Select ${model1.friendlyName}`})).not.toBeChecked()
    const model2Checkbox = within(modelsGroup).getByRole('checkbox', {name: `Select ${model2.friendlyName}`})
    expect(model2Checkbox).not.toBeChecked()

    await userEvent.click(model2Checkbox)

    expect(model2Checkbox).toBeChecked()
    expect(within(publisherTreeItem).getByTestId(`publisher-checkbox-${publisher.id}`)).toBePartiallyChecked()
    const submitButton = within(dialog).getByRole('button', {name: 'Update disabled list'})
    expect(submitButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => mockOrganizationAccessPolicy({isAllowlist: false, allowedModelKeys: [model1.key]}),
    })
    await userEvent.click(submitButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {method: 'DELETE', body: {model_slugs: [model2.key]}},
    )
  })
})

function render(component: JSX.Element, routePayloadOverrides?: Partial<AccessPolicyShowPayload>) {
  const routePayload = mockAccessPolicyShowPayload(routePayloadOverrides)
  return htmlRender(
    <OrganizationAccessPolicyProvider orgDisplayLogin={routePayload.orgDisplayLogin} policy={routePayload.policy}>
      <PublishersProvider models={routePayload.models} publishers={routePayload.publishers}>
        <SelectionProvider models={routePayload.models} publishers={routePayload.publishers}>
          {component}
        </SelectionProvider>
      </PublishersProvider>
    </OrganizationAccessPolicyProvider>,
    {wrapper: withBaseProvidersWrapper()},
  )
}
