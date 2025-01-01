import {render} from '@github-ui/react-core/test-utils'
import {StartTrialDialog, type StartTrialDialogProps} from '../StartTrialDialog'
import {getSelfServeTrialInfo, getTradeScreeningResult} from '../../test-utils/mock-data'
import {screen} from '@testing-library/react'

const defaultProps = {
  onClose: jest.fn(),
  onConfirmStart: jest.fn(),
  isStartingTrial: false,
  selfServeTrialInfo: getSelfServeTrialInfo(),
  tradeScreeningResult: getTradeScreeningResult(),
  ghasFeaturesUrl: 'https://github.com/features/security',
}

const renderStartTrialDialog = (props: Partial<StartTrialDialogProps> = {}) => {
  return render(<StartTrialDialog {...defaultProps} {...props} />)
}

describe('StartTrialDialog Component', () => {
  test('renders the dialog with correct title and description', () => {
    renderStartTrialDialog()

    expect(screen.getByText(/Start your free 30 day trial/)).toBeInTheDocument()
    expect(screen.getByText(/Start trial/)).toBeInTheDocument()
  })

  test('disables the confirm button when isStartingTrial is true', () => {
    renderStartTrialDialog({isStartingTrial: true})

    expect(screen.getByRole('button', {name: 'Starting trial'})).toHaveAttribute('aria-disabled', 'true')
  })

  test('allows starting the trial', async () => {
    const {user} = renderStartTrialDialog()

    const button = screen.getByRole('button', {name: 'Start trial'})
    expect(button).toBeInTheDocument()
    expect(button).not.toBeDisabled()

    await user.click(button)

    expect(defaultProps.onConfirmStart).toHaveBeenCalled()
  })
})

describe('StartTrialDialog Component with no organizations', () => {
  test('renders the no organizations warning message', () => {
    renderStartTrialDialog({
      selfServeTrialInfo: {
        ...defaultProps.selfServeTrialInfo,
        showNoOrgsWarning: true,
      },
    })

    expect(screen.getByText(/You don't currently have any organizations/)).toBeInTheDocument()
  })

  test('still allows enabling the trial', () => {
    renderStartTrialDialog({
      selfServeTrialInfo: {
        ...defaultProps.selfServeTrialInfo,
        showNoOrgsWarning: true,
      },
    })

    const button = screen.getByRole('button', {name: 'Start trial'})
    expect(button).toBeInTheDocument()
    expect(button).not.toBeDisabled()
  })
})

describe('StartTrialDialog Component with trade restricted', () => {
  test('renders the trade restricted message', () => {
    const tradeScreeningResult = {
      isTradeRestricted: true,
      description: 'test',
      title: 'feature unavailable',
      className: 'test-class',
    }
    renderStartTrialDialog({tradeScreeningResult})

    expect(screen.getByText(tradeScreeningResult.title)).toBeInTheDocument()
    expect(screen.getByText(tradeScreeningResult.description)).toBeInTheDocument()
  })

  test('disables the confirm button when trade screening result is trade restricted', () => {
    renderStartTrialDialog({
      tradeScreeningResult: {
        isTradeRestricted: true,
        description: 'test',
        title: 'feature unavailable',
        className: 'test-class',
      },
    })

    expect(screen.getByRole('button', {name: 'Start trial'})).toBeDisabled()
  })
})
