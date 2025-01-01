import {screen} from '@testing-library/react'
import {render as htmlRender, withBaseProvidersWrapper} from '@github-ui/react-core/test-utils'
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

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('PublisherRule', () => {
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

    const {user} = render(<PublisherRule publisher={publisher} />, {
      models: [model1, model2, otherModel],
      orgDisplayLogin,
      policy,
    })

    expect(screen.getByRole('link', {name: 'NeatPub 2 models'})).toBeInTheDocument()
    expect(screen.getByRole('img', {name: 'NeatPub logo'})).toBeInTheDocument()
    const deletePublisherButton = screen.getByRole('button', {name: 'Delete NeatPub'})
    expect(deletePublisherButton).toBeInTheDocument()

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () =>
        mockOrganizationAccessPolicy({isModelsEnabled: true, isAllowlist: false, allowedModelKeys: [otherModel.key]}),
    })
    await user.click(deletePublisherButton)

    expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
      `/organizations/${orgDisplayLogin}/settings/models/access-policy`,
      {
        method: 'POST',
        body: {models_publisher_ids: [publisher.id], catalog_item_keys: [model1.key, model2.key]},
      },
    )
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
