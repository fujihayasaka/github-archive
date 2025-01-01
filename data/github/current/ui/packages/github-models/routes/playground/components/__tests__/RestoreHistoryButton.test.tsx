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
    const button = within(container).getByRole('button', {name: 'Restore last session'})
    expect(button).toBeInTheDocument()

    await user.click(button)

    expect(onClick).toHaveBeenCalledTimes(1)
  })
})
