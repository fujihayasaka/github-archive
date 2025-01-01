import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ClosedSecurityCampaigns} from '../../routes/ClosedSecurityCampaigns'
import {getClosedSecurityCampaignsRoutePayload} from '../../test-utils/mock-data'

test('Renders the number of closed campaigns', async () => {
  const routePayload = getClosedSecurityCampaignsRoutePayload()
  render(<ClosedSecurityCampaigns />, {
    routePayload,
  })
  expect(screen.getByText('42 closed campaigns')).toBeInTheDocument()

  const link = screen.getByRole('link', {
    name: 'Learn more about closed campaigns.',
  })
  expect(link).toBeInTheDocument()
  expect(link.getAttribute('href')).toBe('https://example.com/about-security-campaigns')
})
