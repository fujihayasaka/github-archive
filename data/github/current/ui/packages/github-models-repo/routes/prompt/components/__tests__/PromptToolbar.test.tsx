import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel, mockTokenUsage} from '../../../../test-utils/mock-data'
import {PromptToolbar} from '../PromptToolbar'

const handleRun = jest.fn().mockName('handleRun')
const handleStop = jest.fn().mockName('handleStop')

describe('PromptToolbar', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders', async () => {
    const model = mockModel({capabilities: {tokenCounting: true}})
    const tokenUsage = mockTokenUsage()

    const {user} = render(
      <PromptToolbar model={model} canRun handleStop={handleStop} handleRun={handleRun} tokenUsage={tokenUsage} />,
    )

    expect(screen.getByRole('list', {name: 'View mode'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Edit'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Compare'})).toBeInTheDocument()
    expect(screen.getByTestId('playground-token-usage')).toBeInTheDocument()
    const runButton = screen.getByRole('button', {name: 'Run ( control enter )'})
    expect(runButton).toBeInTheDocument()

    await user.click(runButton)

    expect(handleRun).toHaveBeenCalledTimes(1)
  })

  it('renders disabled', () => {
    render(<PromptToolbar canRun={false} handleRun={handleRun} handleStop={handleStop} disabled />)

    expect(screen.getByRole('list', {name: 'View mode'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Edit'})).toBeDisabled()
    expect(screen.getByRole('button', {name: 'Compare'})).toBeDisabled()
    expect(screen.getByRole('button', {name: 'Run ( control enter )'})).toBeDisabled()
  })

  it('renders with no props', async () => {
    render(<PromptToolbar />)

    expect(screen.getByRole('list', {name: 'View mode'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Edit'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Compare'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Run ( control enter )'})).toBeDisabled()
  })
})
