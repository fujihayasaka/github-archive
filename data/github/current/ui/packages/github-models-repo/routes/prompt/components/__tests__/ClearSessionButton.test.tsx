import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {mockResizeObserver} from '../../../../test-utils/mock-data'
import {PromptCompareManagerContext, type PromptCompareManager} from '../../prompt-compare-manager'
import {ClearSessionButton} from '../ClearSessionButton'

const evalsClear = jest.fn().mockName('evalsClear')

describe('ClearSessionButton', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  beforeEach(() => {
    jest.resetAllMocks()
  })

  it('renders when viewer can clear the session', () => {
    render(<ClearSessionButton />)

    const button = screen.getByRole('button', {name: 'Clear session'})
    expect(button).not.toHaveAttribute('data-inactive')
  })

  it('renders when viewer cannot clear the session', async () => {
    const {user} = render(<ClearSessionButton disabled />)

    const button = screen.getByRole('button', {name: 'Clear session'})
    expect(button).toHaveAttribute('data-inactive', 'true')

    await user.click(button)

    expect(evalsClear).not.toHaveBeenCalled()
  })

  it('asks to confirm before clearing the session', async () => {
    const {user} = render(<ClearSessionButton />)

    const button = screen.getByRole('button', {name: 'Clear session'})

    await user.click(button)
    expect(evalsClear).toHaveBeenCalledTimes(0)

    const confirmDialog = screen.getByRole('alertdialog', {name: 'Clear current session?'})
    const clearbutton = within(confirmDialog).getByRole('button', {name: 'Clear'})

    await user.click(clearbutton)

    expect(evalsClear).toHaveBeenCalledTimes(1)
    expect(confirmDialog).not.toBeInTheDocument()
  })

  it('does not clear the session, when the user cancels the dialog', async () => {
    const {user} = render(<ClearSessionButton />)

    const button = screen.getByRole('button', {name: 'Clear session'})

    await user.click(button)
    expect(evalsClear).toHaveBeenCalledTimes(0)

    const confirmDialog = screen.getByRole('alertdialog', {name: 'Clear current session?'})
    const cancelButton = within(confirmDialog).getByRole('button', {name: 'Cancel'})

    await user.click(cancelButton)

    expect(evalsClear).toHaveBeenCalledTimes(0)
    expect(confirmDialog).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, opts: TestRenderOptions = {}) {
  const manager = {} as PromptCompareManager
  manager.evalsClear = evalsClear

  return htmlRender(component, {
    ...opts,
    wrapper({children}) {
      return <PromptCompareManagerContext.Provider value={manager}>{children}</PromptCompareManagerContext.Provider>
    },
  })
}
