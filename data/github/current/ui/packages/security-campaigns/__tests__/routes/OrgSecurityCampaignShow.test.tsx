import {screen, waitFor} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {OrgSecurityCampaignShow} from '../../routes/OrgSecurityCampaignShow'
import {getOrgSecurityCampaignShowRoutePayload, getSecurityCampaign} from '../../test-utils/mock-data'

jest.mock('../../components/OrgDraftSecurityCampaign', () => ({
  OrgDraftSecurityCampaign: () => <>Mock OrgDraftSecurityCampaign</>,
}))

jest.mock('../../components/OrgPublishedSecurityCampaign', () => ({
  OrgPublishedSecurityCampaign: () => <>Mock OrgPublishedSecurityCampaign</>,
}))

test('It renders the OrgDraftSecurityCampaign component if the campaign is draft', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign({creationQuery: '', publishedAt: null}),
  }

  render(<OrgSecurityCampaignShow />, {
    routePayload,
  })

  await waitFor(() => {
    expect(screen.getByText('Mock OrgDraftSecurityCampaign')).toBeInTheDocument()
  })
})

test('It renders the OrgPublishedSecurityCampaign component if the campaign is published', async () => {
  const routePayload = {
    ...getOrgSecurityCampaignShowRoutePayload(),
    campaign: getSecurityCampaign(),
  }

  render(<OrgSecurityCampaignShow />, {
    routePayload,
  })

  await waitFor(() => {
    expect(screen.getByText('Mock OrgPublishedSecurityCampaign')).toBeInTheDocument()
  })
})
