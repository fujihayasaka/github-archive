import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundCard} from '../PlaygroundCard'

describe('PlaygroundCard', () => {
  const onClick = jest.fn()

  test('renders', async () => {
    const sample = 'hello world'

    const {container, user} = render(<PlaygroundCard onClick={onClick} sample={sample} size="small" />)

    const textEl = within(container).getByText(sample)
    expect(textEl).toBeInTheDocument()
    expect(onClick).not.toHaveBeenCalled()

    await user.click(textEl)

    expect(onClick).toHaveBeenCalledTimes(1)
  })
})
