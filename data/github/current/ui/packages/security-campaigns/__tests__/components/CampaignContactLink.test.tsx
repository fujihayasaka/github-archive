import {screen} from '@testing-library/react'
import {render as reactRender} from '@github-ui/react-core/test-utils'
import {CampaignContactLink, type CampaignContactLinkProps} from '../../components/CampaignContactLink'

const defaultProps: CampaignContactLinkProps = {
  contactLink: 'http://example.com',
  teamCount: 0,
  userCount: 1,
}

const render = (props?: Partial<CampaignContactLinkProps>) =>
  reactRender(<CampaignContactLink {...defaultProps} {...props} />)

test('Renders singular manager', () => {
  render()

  expect(screen.queryByText('Contact campaign managers')).not.toBeInTheDocument()
  expect(screen.getByText('Contact campaign manager')).toBeInTheDocument()
})

test('Renders multiple manager', () => {
  render({userCount: 2})

  expect(screen.getByText('Contact campaign managers')).toBeInTheDocument()
})

test('Pluralizes with one team manager', () => {
  render({teamCount: 1, userCount: 0})

  expect(screen.getByText('Contact campaign managers')).toBeInTheDocument()
})
