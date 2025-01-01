import {render, screen} from '@testing-library/react'
import {MisconfiguredOrgPlanBanner} from '../MisconfiguredOrgPlanBanner'

describe('<MisconfiguredOrgPlanBanner />', () => {
  beforeEach(() => {
    const portalRoot = global.document.createElement('div')

    portalRoot.setAttribute('id', 'js-flash-container')
    portalRoot.setAttribute('data-testid', 'portal-container')
    global.document.body.appendChild(portalRoot)
  })

  afterEach(() => {
    const portalRoot = screen.getByTestId('portal-container')

    if (portalRoot) {
      global.document.body.removeChild(portalRoot)
    }
  })

  it('renders nothing if the banner is not visible', () => {
    const {container} = render(<MisconfiguredOrgPlanBanner visible={false} slug="test-slug" />)
    expect(container).toBeEmptyDOMElement()
  })

  it('renders the banner if the banner is visible', () => {
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })
    render(<MisconfiguredOrgPlanBanner visible slug="test-slug" />)
    expect(screen.getByTestId('cfb-unconfigured-org-banner')).toBeInTheDocument()
  })

  it('renders the banner with the correct link', () => {
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })
    const portalRoot = global.document.createElement('div')

    portalRoot.setAttribute('id', 'js-flash-container')
    global.document.body.appendChild(portalRoot)

    render(
      <div>
        <div id="js-flash-container" />
        <MisconfiguredOrgPlanBanner visible slug="test-slug" />
      </div>,
    )
    expect(screen.getByRole('link', {name: "enterprise's settings page"})).toHaveAttribute(
      'href',
      '/enterprises/test-slug/settings/copilot',
    )
  })
})
