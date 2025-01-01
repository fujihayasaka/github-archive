import {render, screen} from '@testing-library/react'
import {PlanInfo} from '../../apps/sidebar/PlanInfo'
import {mockPlanInfo, mockPlan} from '../../../test-utils/mock-data'

describe('PlanInfo', () => {
  it('renders the SidebarPlanInfo section', () => {
    render(<PlanInfo planInfo={mockPlanInfo()} isCopilotApp />)
    expect(screen.getByTestId('apps-planinfo')).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 2, name: 'Pricing'})).toBeInTheDocument()
  })

  it('renders singular plan info if only one plan', () => {
    render(
      <PlanInfo
        planInfo={mockPlanInfo({
          plans: [
            mockPlan({
              name: 'Free',
            }),
          ],
        })}
        isCopilotApp
      />,
    )
    expect(screen.getByText('Free plan available.')).toBeInTheDocument()
  })

  it('renders plural plan info if there are multiple plans', () => {
    render(
      <PlanInfo
        planInfo={mockPlanInfo({
          plans: [
            mockPlan({
              name: 'Free',
            }),
            mockPlan({
              name: 'Paid',
            }),
          ],
        })}
        isCopilotApp
      />,
    )
    expect(screen.getByText('Free and Paid plans available.')).toBeInTheDocument()
  })

  it('renders copilot information if app is a copilot app', () => {
    render(<PlanInfo planInfo={mockPlanInfo()} isCopilotApp />)
    expect(screen.getByText('GitHub Copilot license')).toHaveAttribute(
      'href',
      'https://github.com/features/copilot/plans',
    )
  })

  it('does not render copilot information if app is not a copilot app', () => {
    render(<PlanInfo planInfo={mockPlanInfo()} isCopilotApp={false} />)
    expect(screen.queryByText('GitHub Copilot license')).not.toBeInTheDocument()
  })
})
