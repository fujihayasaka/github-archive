import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundCard} from '../PlaygroundCard'

describe('PlaygroundCard', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  const onAction = jest.fn()

  test('renders', async () => {
    const sample = 'hello world'

    const {container, user} = render(<PlaygroundCard onAction={onAction} sample={sample} size="small" />)

    const textEl = within(container).getByTestId('playground-card')
    expect(textEl).toBeInTheDocument()
    expect(onAction).not.toHaveBeenCalled()

    await user.click(textEl)

    expect(onAction).toHaveBeenCalledTimes(1)
  })

  test('handles tab for keyboard navigation', async () => {
    const sample = 'hello world'

    const {container, user} = render(<PlaygroundCard onAction={onAction} sample={sample} size="small" />)
    const playgroundContainer = within(container).getByTestId('playground-card')

    expect(playgroundContainer).toBeInTheDocument()
    expect(onAction).not.toHaveBeenCalled()

    await user.tab()
    expect(playgroundContainer).toHaveFocus()

    await user.keyboard('[Enter]')
    expect(onAction).toHaveBeenCalledTimes(1)
  })
})
