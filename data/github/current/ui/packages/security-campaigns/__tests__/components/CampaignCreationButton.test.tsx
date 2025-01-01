import type {CampaignCreationButtonProps} from '../../components/CampaignCreationButton'
import {screen} from '@testing-library/react'
import {CampaignCreationButton} from '../../components/CampaignCreationButton'
import {render} from '@github-ui/react-core/test-utils'
import {securityCampaignsOrgNewCampaignPath} from '@github-ui/paths'

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

describe('CampaignCreationButton', () => {
  const defaultProps: CampaignCreationButtonProps = {
    organizationLogin: 'octodemo',
    maxCampaignsReached: false,
    maxOpenCampaigns: 10,
    maxDraftCampaigns: 10,
    hasSpam: false,
    setIsTemplatesDialogOpen: jest.fn(),
  }

  it('renders the button and menu items', async () => {
    const {user} = render(<CampaignCreationButton {...defaultProps} />)

    expect(screen.getByText('Create campaign')).toBeInTheDocument()

    await user.click(screen.getByText('Create campaign'))
    expect(screen.getByText('From template')).toBeInTheDocument()
    expect(screen.getByText('From code scanning filters')).toBeInTheDocument()
  })

  it('disables the button when maxCampaignsReached is true', async () => {
    const {user} = render(<CampaignCreationButton {...defaultProps} maxCampaignsReached />)

    expect(screen.getByText('Limit of 10 open and 10 draft campaigns has been reached')).toBeInTheDocument()
    const createCampaignButton = screen.getByRole('button', {name: 'Create campaign'})
    expect(createCampaignButton).toHaveAttribute('data-inactive', 'true')

    await user.click(createCampaignButton)

    expect(screen.queryAllByRole('menuitem')).toHaveLength(0)
  })

  it('calls setIsTemplatesDialogOpen when "From template" is selected', async () => {
    const {user} = render(<CampaignCreationButton {...defaultProps} />)

    await user.click(screen.getByText('Create campaign'))
    await user.click(screen.getByText('From template'))

    expect(defaultProps.setIsTemplatesDialogOpen).toHaveBeenCalledWith(true)
  })

  it('navigates to the new campaign path when "From code scanning filters" is selected', async () => {
    const {user} = render(<CampaignCreationButton {...defaultProps} />)

    await user.click(screen.getByText('Create campaign'))
    await user.click(screen.getByText('From code scanning filters'))

    expect(navigateFn).toHaveBeenCalledWith(securityCampaignsOrgNewCampaignPath({org: 'octodemo'}))
  })

  it('shows spam message when hasSpam is true and max campaigns reached', () => {
    render(<CampaignCreationButton {...defaultProps} hasSpam maxCampaignsReached />)
    expect(screen.getByText('Limit of 10 open and 10 draft and spam campaigns has been reached')).toBeInTheDocument()
  })
})
