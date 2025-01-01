import {render} from '@github-ui/react-core/test-utils'
import {BannerProvider, useBannerContext} from '../BannerProvider'
import {screen} from '@testing-library/react'

const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => navigateFn,
  }
})

const TestComponent = () => {
  const {navigate, showBanner} = useBannerContext()
  return (
    <>
      <button onClick={() => showBanner({message: 'Test message', variant: 'success'})}>Show Banner</button>
      <button
        onClick={() =>
          navigate('/role-assignments', {replace: true}, {message: 'Navigate message', variant: 'success'})
        }
      >
        Navigate
      </button>
    </>
  )
}

describe('BannerProvider', () => {
  it('renders children', () => {
    render(
      <BannerProvider>
        <div>Child Component</div>
      </BannerProvider>,
    )
    expect(screen.getByText('Child Component')).toBeInTheDocument()
    expect(screen.queryByTestId('banner')).not.toBeInTheDocument()
  })

  it('shows banner when showBanner is called and hides banner when onDismiss is called', async () => {
    const {user} = render(
      <BannerProvider>
        <TestComponent />
      </BannerProvider>,
    )

    expect(screen.queryByTestId('banner')).not.toBeInTheDocument()
    await user.click(screen.getByText('Show Banner'))

    const banner = screen.getByTestId('banner')
    expect(banner).toBeInTheDocument()
    expect(banner).toHaveTextContent('Test message')

    await user.click(screen.getByRole('button', {name: /Dismiss/i}))
    expect(screen.queryByTestId('banner')).not.toBeInTheDocument()
  })

  it('navigates and shows banner when navigate is called', async () => {
    const {user} = render(
      <BannerProvider>
        <TestComponent />
      </BannerProvider>,
    )

    expect(screen.queryByTestId('banner')).not.toBeInTheDocument()
    await user.click(screen.getByText('Navigate'))

    expect(navigateFn).toHaveBeenCalledWith('/role-assignments', {replace: true})
    const banner = screen.getByTestId('banner')
    expect(banner).toBeInTheDocument()
    expect(banner).toHaveTextContent('Navigate message')
  })

  it('throws error when useBannerContext is used outside of BannerProvider', () => {
    const consoleErrorSpy = jest.spyOn(console, 'error').mockImplementation(() => {})

    const TestComponentOutsideProvider = () => {
      useBannerContext()
      return null
    }

    expect(() => render(<TestComponentOutsideProvider />)).toThrow(
      'useBannerContext must be used within a BannerProvider',
    )

    expect(consoleErrorSpy).toHaveBeenCalled()

    consoleErrorSpy.mockRestore()
  })
})
