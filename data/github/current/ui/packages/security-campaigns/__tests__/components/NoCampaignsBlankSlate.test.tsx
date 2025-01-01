import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {NoCampaignsBlankSlate} from '../../components/NoCampaignsBlankSlate'

describe('NoCampaignsBlankSlate', () => {
  test('renders correctly when creation is not allowed', () => {
    render(
      <NoCampaignsBlankSlate
        creationAllowed={false}
        organizationLogin="octodemo"
        setIsTemplatesDialogOpen={jest.fn()}
        maxCampaignsReached={false}
        maxDraftCampaigns={10}
        maxOpenCampaigns={10}
        aboutCampaignsDocsUrl="https://github.com"
        hasSpam={false}
      />,
    )

    expect(screen.getByText('No campaigns available')).toBeInTheDocument()
    expect(
      screen.getByText(
        'Security campaigns help teams remediate code scanning alerts with the help of Copilot Autofix.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('Learn more about security campaigns')).toHaveAttribute('href', 'https://github.com')
    expect(screen.queryByText('Start a new campaign')).not.toBeInTheDocument()
  })

  test('renders correctly when creation is allowed', () => {
    render(
      <NoCampaignsBlankSlate
        creationAllowed
        organizationLogin="octodemo"
        setIsTemplatesDialogOpen={jest.fn()}
        maxCampaignsReached={false}
        maxDraftCampaigns={10}
        maxOpenCampaigns={10}
        aboutCampaignsDocsUrl="https://github.com"
        hasSpam={false}
      />,
    )

    expect(screen.getByText('Create campaign')).toBeInTheDocument()
    expect(
      screen.getByText(
        'Start a new security campaign to help teams remediate code scanning alerts with the help of Copilot Autofix.',
      ),
    ).toBeInTheDocument()
    expect(screen.getByText('Learn more about security campaigns')).toHaveAttribute('href', 'https://github.com')
    expect(screen.getByText('Create campaign')).toBeInTheDocument()
  })
})
