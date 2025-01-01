import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {HeaderButton, HeaderLinkButton} from '../../apps/HeaderButton'
import {mockPlanInfo} from '../../../test-utils/mock-data'
import checkCanInstall from '../../../utilities/check-can-install'

jest.mock('../../../utilities/check-can-install')

function renderComponent(Component: React.FC<any>, {canInstall = true, disabled = false, href = ''} = {}) {
  ;(checkCanInstall as jest.Mock).mockReturnValue({canInstall})
  return render(
    <Component planInfo={mockPlanInfo()} disabled={disabled} href={href}>
      Click Me
    </Component>,
  )
}

describe('HeaderButton', () => {
  it('renders the component with the children', () => {
    renderComponent(HeaderButton, {canInstall: true})
    expect(screen.getByText('Click Me')).toBeInTheDocument()
  })

  it('is disabled when the user can not install the app', () => {
    renderComponent(HeaderButton, {canInstall: false})
    expect(screen.getByRole('button', {name: 'Click Me'})).toBeDisabled()
  })

  it('is disabled when the user can install, but disabled prop is passed', () => {
    renderComponent(HeaderButton, {canInstall: true, disabled: true})
    expect(screen.getByRole('button', {name: 'Click Me'})).toBeDisabled()
  })

  it('renders enabled when the user can install and no disabled prop is passed', () => {
    renderComponent(HeaderButton, {canInstall: true})
    expect(screen.getByRole('button', {name: 'Click Me'})).toBeEnabled()
  })

  it('is accessible when disabled', () => {
    renderComponent(HeaderButton, {canInstall: false})
    expect(screen.getByRole('button', {name: 'Click Me'})).toHaveAttribute('aria-disabled', 'true')
    expect(screen.getByRole('button', {name: 'Click Me'}).getAttribute('aria-describedby')).toContain(
      'install-unavailable-reason',
    )
  })

  it('excludes aria-describedby when enabled', () => {
    renderComponent(HeaderButton, {canInstall: true})
    expect(screen.getByRole('button', {name: 'Click Me'}).getAttribute('aria-describedby')).not.toContain(
      'install-unavailable-reason',
    )
  })
})

describe('HeaderLinkButton', () => {
  it('renders the component with the children', () => {
    renderComponent(HeaderLinkButton, {canInstall: true})
    expect(screen.getByText('Click Me')).toBeInTheDocument()
  })

  it('is disabled when the user can not install the app', () => {
    renderComponent(HeaderLinkButton, {canInstall: false})
    expect(screen.getByTestId('header-link-button')).toHaveAttribute('disabled')
  })

  it('is disabled when the user can install, but disabled prop is passed', () => {
    renderComponent(HeaderLinkButton, {canInstall: true, disabled: true})
    expect(screen.getByTestId('header-link-button')).toHaveAttribute('disabled')
  })

  it('renders enabled when the user can install and no disabled prop is passed', () => {
    renderComponent(HeaderLinkButton, {canInstall: true})
    expect(screen.getByTestId('header-link-button')).not.toHaveAttribute('disabled')
  })

  it('is accessible when disabled', () => {
    renderComponent(HeaderLinkButton, {canInstall: false})
    expect(screen.getByTestId('header-link-button').getAttribute('aria-describedby')).toContain(
      'install-unavailable-reason',
    )
  })

  it('excludes aria-describedby when enabled', () => {
    renderComponent(HeaderLinkButton, {canInstall: true})
    expect(screen.getByTestId('header-link-button').getAttribute('aria-describedby')).not.toContain(
      'install-unavailable-reason',
    )
  })

  it('includes the href when passed', () => {
    renderComponent(HeaderLinkButton, {canInstall: true, href: '#test-id'})
    expect(screen.getByTestId('header-link-button')).toHaveAttribute('href', '#test-id')
  })
})
