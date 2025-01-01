import {AdvancedSecurityFeatures, type AdvancedSecurityFeaturesProps} from '../AdvancedSecurityFeatures'
import {getSelfServeTrialInfo} from '../../test-utils/mock-data'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'

const defaultProps = {
  selfServeTrialInfo: getSelfServeTrialInfo(),
  isTeams: false,
  ghasFeaturesUrl: 'https://github.com/features/security',
}
const renderAdvancedSecurityFeatures = (props: Partial<AdvancedSecurityFeaturesProps> = {}) => {
  return render(<AdvancedSecurityFeatures {...defaultProps} {...props} />)
}

describe('AdvancedSecurityFeatures Component', () => {
  test('renders the component with correct title and description', () => {
    renderAdvancedSecurityFeatures()

    expect(screen.getByText(/Enable GitHub Advanced Security/)).toBeInTheDocument()
    expect(screen.getByText('Secret Protection')).toBeInTheDocument()
    expect(screen.getByText('Code Security')).toBeInTheDocument()
  })

  test('sends analytics event on learn more click', async () => {
    const {user} = renderAdvancedSecurityFeatures()

    const learnMoreLink = screen.getByRole('link', {name: /Learn more about Secret Protection/i})
    expect(learnMoreLink).toBeInTheDocument()
    await user.click(learnMoreLink)

    expectAnalyticsEvents({
      type: 'analytics.click',
      data: {
        category: 'advanced_security_self_serve_trial',
        action: 'click_security_features',
        label: 'ref_cta:features;ref_loc:enterprise_licensing',
      },
    })
  })
})
