import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {HeartIcon, SparkleFillIcon} from '@primer/octicons-react'
import {GetStartedBox} from '../GetStartedBox'

const onClick = jest.fn().mockName('onClick')

describe('GetStartedBox', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders with a link', () => {
    render(<GetStartedBox icon={HeartIcon} callToAction="Eat at Joe's" href="/foo/bar" />)

    expect(screen.getByRole('link', {name: "Eat at Joe's"})).toHaveAttribute('href', '/foo/bar')
    expect(screen.getByTestId('get-started-icon')).toHaveClass('octicon-heart')
    expect(screen.queryByRole('button')).not.toBeInTheDocument()
  })

  it('renders with a button', async () => {
    const {user} = render(<GetStartedBox icon={SparkleFillIcon} callToAction="Play Mass Effect" onClick={onClick} />)

    const button = screen.getByRole('button', {name: 'Play Mass Effect'})
    expect(button).toBeInTheDocument()
    expect(screen.getByTestId('get-started-icon')).toHaveClass('octicon-sparkle-fill')
    expect(screen.queryByRole('link')).not.toBeInTheDocument()
    expect(onClick).not.toHaveBeenCalled()

    await user.click(button)

    expect(onClick).toHaveBeenCalledTimes(1)
  })

  it('renders only a link when both href and onClick are given', () => {
    render(
      <GetStartedBox icon={HeartIcon} callToAction="Hug a librarian" href="https://example.com" onClick={onClick} />,
    )

    expect(screen.getByRole('link', {name: 'Hug a librarian'})).toHaveAttribute('href', 'https://example.com')
    expect(screen.getByTestId('get-started-icon')).toHaveClass('octicon-heart')
    expect(screen.queryByRole('button')).not.toBeInTheDocument()
    expect(onClick).not.toHaveBeenCalled()
  })
})
