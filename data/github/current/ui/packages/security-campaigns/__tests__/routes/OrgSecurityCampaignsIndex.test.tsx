import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {OrgSecurityCampaignsIndex} from '../../routes/OrgSecurityCampaignsIndex'
import {getOrgSecurityCampaignsIndexRoutePayload} from '../../test-utils/mock-data'

jest.setTimeout(10_000)

test('Renders campaigns heading', async () => {
  const routePayload = getOrgSecurityCampaignsIndexRoutePayload()

  render(<OrgSecurityCampaignsIndex />, {routePayload})

  expect(screen.getByRole('heading', {level: 2})).toHaveTextContent('Campaigns')
})
