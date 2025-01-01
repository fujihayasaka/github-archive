import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {sendEvent} from '@github-ui/hydro-analytics'
import {mockResizeObserver} from '../../../../test-utils/mock-data'
import {CompareForkPromptClicked, CompareNewPromptClicked} from '../../types'
import {AddPromptMenu} from '../AddPromptMenu'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

const onAdd = jest.fn().mockName('onAdd')
const onFork = jest.fn().mockName('onFork')

describe('AddPromptMenu', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders', async () => {
    const {user} = render(<AddPromptMenu totalPrompts={1} onAdd={onAdd} onFork={onFork} />)

    const menuToggle = screen.getByRole('button', {name: 'Add prompt'})
    expect(menuToggle).toBeInTheDocument()
    expect(screen.queryByRole('menu', {name: 'Add prompt'})).not.toBeInTheDocument()

    await user.click(menuToggle)

    const menu = screen.getByRole('menu', {name: 'Add prompt'})
    expect(menu).toBeInTheDocument()
    expect(within(menu).getByRole('menuitem', {name: 'Copy original prompt'})).toBeInTheDocument()
    expect(within(menu).getByRole('menuitem', {name: 'New prompt'})).toBeInTheDocument()
    expect(onAdd).not.toHaveBeenCalled()
    expect(onFork).not.toHaveBeenCalled()
  })

  it('emits analytics event on fork prompt click', async () => {
    const {user} = render(<AddPromptMenu totalPrompts={5} onAdd={onAdd} onFork={onFork} />)

    await user.click(screen.getByRole('button', {name: 'Add prompt'}))
    await user.click(screen.getByRole('menuitem', {name: 'Copy original prompt'}))

    expect(onAdd).not.toHaveBeenCalled()
    expect(onFork).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(CompareForkPromptClicked, {totalPrompts: 5})
  })

  it('emits analytics event on new prompt click', async () => {
    const {user} = render(<AddPromptMenu totalPrompts={1} onAdd={onAdd} onFork={onFork} />)

    await user.click(screen.getByRole('button', {name: 'Add prompt'}))
    await user.click(screen.getByRole('menuitem', {name: 'New prompt'}))

    expect(onFork).not.toHaveBeenCalled()
    expect(onAdd).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(CompareNewPromptClicked, {totalPrompts: 1})
  })

  it('can add a new prompt if totalPrompts is less than 20', async () => {
    const {user} = render(<AddPromptMenu totalPrompts={19} onAdd={onAdd} onFork={onFork} />)

    await user.click(screen.getByRole('button', {name: 'Add prompt'}))
    const newPrompt = screen.getByRole('menuitem', {name: 'New prompt'})

    expect(newPrompt).not.toHaveAttribute('aria-disabled')
  })

  it('cannot add a new prompt if totalPrompts is more than or equal to 20', async () => {
    const {user} = render(<AddPromptMenu totalPrompts={20} onAdd={onAdd} onFork={onFork} />)

    await user.click(screen.getByRole('button', {name: 'Add prompt'}))
    const newPrompt = screen.getByRole('menuitem', {name: 'New prompt'})

    expect(newPrompt).toHaveAttribute('aria-disabled', 'true')
  })
})
