import {render} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {RestoreHistoryButton} from '../RestoreHistoryButton'

const onClick = jest.fn()

describe('RestoreHistoryButton', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders', async () => {
    const {container, user} = render(<RestoreHistoryButton onClick={onClick} />)

    expect(onClick).not.toHaveBeenCalled()
    const buttons = within(container).getAllByRole('button', {name: 'Restore last session'})

    expect(buttons).toHaveLength(2)

    for (const button of buttons) {
      await user.click(button)
    }

    expect(onClick).toHaveBeenCalledTimes(2)
  })
})
