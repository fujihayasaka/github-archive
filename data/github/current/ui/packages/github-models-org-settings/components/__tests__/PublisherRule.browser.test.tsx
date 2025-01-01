import {describe, it, expect, afterEach} from '@github-ui/tests'
import {userEvent} from '@github-ui/tests/browser'
import {vi} from 'vitest'
import {screen, render as htmlRender} from '@testing-library/react'
import {withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
import type {AccessPolicyShowPayload} from '../../types'
import {OrganizationAccessPolicyProvider} from '../../contexts/OrganizationAccessPolicyContext'
import {
  mockAccessPolicyShowPayload,
  mockModel,
  mockOrganizationAccessPolicy,
  mockPublisher,
} from '../../test-utils/mocks'
import {PublishersProvider} from '../../contexts/PublishersContext'
import {PublisherRule} from '../PublisherRule'

const mockVerifiedFetchJSON = vi.fn().mockName('verifiedFetchJSON')

vi.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
    reactFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('PublisherRule', () => {
  afterEach(() => {
    vi.resetAllMocks()
  })

  it('renders', async () => {
    const orgDisplayLogin = 'someOrg'
    const publisher = mockPublisher({name: 'NeatPub', totalModels: 2})
    const model1 = mockModel({publisherId: publisher.id, key: 'azureml/foo'})
    const model2 = mockModel({publisherId: publisher.id, key: 'azureml/bar'})
    const otherModel = mockModel({publisherId: publisher.id + 1, key: 'azureml/baz'})
    const policy = mockOrganizationAccessPolicy({
      allowedModelKeys: [model1.key, model2.key, otherModel.key],
      isAllowlist: false,
    })

    render(<PublisherRule publisher={publisher} />, {
      models: [model1, model2, otherModel],
      orgDisplayLogin,
      policy,
    })

    expect(screen.getByRole('link', {name: 'NeatPub 2models'})).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'NeatPub logo'})).toBeInTheDocument()
    const deletePublisherButton = screen.getByRole('button', {name: 'Delete NeatPub'})
    expect(deletePublisherButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () =>
        mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false, allowedModelKeys: [otherModel.key]}),
    })
    await userEvent.click(deletePublisherButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {
        method: 'POST',
        body: {models_publisher_ids: [publisher.id], model_slugs: [model1.key, model2.key]},
      },
    )
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
