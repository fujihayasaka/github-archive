import {render} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {AddModelButton} from '../AddModelButton'
import {mockModelState} from './mocks'

const onClick = jest.fn()

describe('AddModelButton', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders enabled button when no models are loading', async () => {
    const modelState = mockModelState({isLoading: false})

    const {container, user} = render(<AddModelButton models={[modelState]} onClick={onClick} />)

    const button = within(container).getByRole('button', {name: 'Compare', hidden: true})
    expect(button).toBeInTheDocument()
    expect(onClick).not.toHaveBeenCalled()
    expect(button).toBeEnabled()

    await user.click(button)

    expect(onClick).toHaveBeenCalledTimes(1)
  })

  test('renders disabled button when a model is loading', () => {
    const modelState = mockModelState({isLoading: true})

    const {container} = render(<AddModelButton models={[modelState]} onClick={onClick} />)

    const button = within(container).getByRole('button', {name: 'Compare', hidden: true})
    expect(button).toBeInTheDocument()
    expect(button).toBeDisabled()
    expect(onClick).not.toHaveBeenCalled()
  })
})
