import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import InstallDialog from '../../apps/InstallDialog'
import {mockPlan, mockPlanInfo} from '../../../test-utils/mock-data'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'

describe('InstallDialog', () => {
  test('Renders the dialog when open', () => {
    render(
      <InstallDialog
        open
        onClose={jest.fn()}
        planInfo={mockPlanInfo()}
        app={mockAppListing()}
        setSelectedAccount={() => {}}
      />,
    )

    expect(screen.getByText('Configure your installation')).toBeInTheDocument()
    // expect close and submit buttons
    expect(screen.getAllByRole('button')).toHaveLength(2)
  })

  test('Does not render the dialog when closed', () => {
    render(
      <InstallDialog
        open={false}
        onClose={jest.fn()}
        planInfo={mockPlanInfo()}
        app={mockAppListing()}
        setSelectedAccount={() => {}}
      />,
    )

    expect(screen.queryByText('Configure your installation')).not.toBeInTheDocument()
  })

  test('Does not render the dialog if selected plan is not found', () => {
    render(
      <InstallDialog
        open
        onClose={jest.fn()}
        planInfo={mockPlanInfo({
          plans: [mockPlan({id: '1000'})],
        })}
        app={mockAppListing()}
        setSelectedAccount={() => {}}
      />,
    )

    expect(screen.queryByText('Configure your installation')).not.toBeInTheDocument()
  })

  describe('When there is more than one plan', () => {
    test('Renders the plan radio group', () => {
      render(
        <InstallDialog
          open
          onClose={jest.fn()}
          planInfo={mockPlanInfo({
            viewerHasPurchased: false,
            viewerHasPurchasedForAllOrganizations: false,
            plans: [mockPlan(), mockPlan({id: '2'})],
          })}
          app={mockAppListing()}
          setSelectedAccount={() => {}}
        />,
      )

      expect(screen.getByTestId('plans-radio-group')).toBeInTheDocument()
    })

    test('Selecting new plan updates the selected plan', async () => {
      const plans = [
        mockPlan({name: 'Free', id: '1', isPaid: false, price: '$0'}),
        mockPlan({name: 'Cheap', id: '2', isPaid: true, perUnit: false, price: '$5'}),
        mockPlan({name: 'Expensive', id: '3', isPaid: true, price: '$10'}),
      ]

      const {user} = render(
        <InstallDialog
          open
          onClose={() => {}}
          planInfo={mockPlanInfo({plans})}
          app={mockAppListing()}
          setSelectedAccount={() => {}}
        />,
      )

      // ensure the price is not rendered initially (free plan)
      expect(screen.queryByTestId('plan-form-price')).not.toBeInTheDocument()

      // click the cheap plan
      const newPlanRadio = screen.getByRole('radio', {name: /Cheap/})
      await user.click(newPlanRadio)

      // ensure the new price is rendered
      expect(screen.getByTestId('plan-form-price')).toHaveTextContent('$5')
    })
  })

  test('Does not render the plan radio group if only one plan', () => {
    render(
      <InstallDialog
        open
        onClose={jest.fn()}
        planInfo={mockPlanInfo({
          viewerHasPurchased: false,
          viewerHasPurchasedForAllOrganizations: false,
          plans: [mockPlan()],
        })}
        app={mockAppListing()}
        setSelectedAccount={() => {}}
      />,
    )

    expect(screen.queryByTestId('plans-radio-group')).not.toBeInTheDocument()
  })

  test('Renders the plan form', () => {
    render(
      <InstallDialog
        open
        onClose={jest.fn()}
        planInfo={mockPlanInfo({
          viewerHasPurchased: false,
          viewerHasPurchasedForAllOrganizations: false,
          plans: [mockPlan()],
        })}
        app={mockAppListing()}
        setSelectedAccount={() => {}}
      />,
    )

    expect(screen.getByTestId('plan-form')).toBeInTheDocument()
  })
})
