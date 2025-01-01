import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {Header} from '../../apps/Header'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockPlanInfo} from '../../../test-utils/mock-data'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useResponsiveValue} from '@primer/react'

jest.mock('@github-ui/react-core/use-feature-flag')
function mockUseFeatureFlag(flags: {[key: string]: boolean}): void {
  ;(useFeatureFlag as jest.Mock).mockImplementation(flagName => flags[flagName])
}

jest.mock('@primer/react', () => ({
  ...jest.requireActual('@primer/react'),
  useResponsiveValue: jest.fn(),
}))
function mockIsMobile(value: boolean) {
  ;(useResponsiveValue as jest.Mock).mockImplementation(() => value)
}

function renderComponent({
  userCanEdit = true,
  copilotApp = false,
  freeInstall = false,
  isMobile = false,
  planInfoOverride = {},
} = {}) {
  mockUseFeatureFlag({
    marketplace_free_install: freeInstall,
  })
  mockIsMobile(isMobile)
  render(
    <Header app={mockAppListing({copilotApp})} planInfo={mockPlanInfo(planInfoOverride)} userCanEdit={userCanEdit} />,
  )
}

describe('Header', () => {
  test('Renders the overview header', () => {
    renderComponent()

    expect(screen.getByTestId('overview-header')).toBeInTheDocument()
  })

  test('Renders the about section', () => {
    renderComponent()

    expect(screen.getByTestId('about')).toBeInTheDocument()
  })

  test('Renders the setup button', () => {
    renderComponent()

    expect(screen.getByTestId('setup-button')).toBeInTheDocument()
  })

  test('Renders the action menu', () => {
    renderComponent()

    expect(screen.getByTestId('listing-actions-button')).toBeInTheDocument()
  })

  test('Renders the tags section', () => {
    renderComponent()

    expect(screen.getByTestId('tags')).toBeInTheDocument()
  })

  test('Renders the verified owner section', () => {
    renderComponent()

    expect(screen.getByTestId('verified-owner')).toBeInTheDocument()
  })

  test('Renders the plan info section', () => {
    renderComponent()

    expect(screen.getByTestId('apps-planinfo')).toBeInTheDocument()
  })

  describe('When the app is a Copilot app', () => {
    it('Renders the works with section', () => {
      renderComponent({copilotApp: true})

      expect(screen.getByTestId('apps-works-with')).toBeInTheDocument()
    })

    describe('When the marketplace_free_install flag is enabled', () => {
      it('Renders the install unavailable banner on a narrow screen', () => {
        renderComponent({
          copilotApp: true,
          freeInstall: true,
          planInfoOverride: {isRegularEmuUser: true},
          isMobile: true,
        })

        expect(screen.getByText('Install unavailable')).toBeInTheDocument()
      })

      it('Renders disabled add button described by the unavailable reason', () => {
        renderComponent({
          copilotApp: true,
          freeInstall: true,
          planInfoOverride: {isRegularEmuUser: true},
          isMobile: true,
        })
        const addButton = screen.getByRole('button', {name: 'Set up a free trial'})

        expect(addButton).toBeDisabled()
        expect(addButton).toHaveAttribute('aria-describedby', expect.stringContaining('install-unavailable-reason'))
      })

      it('Does not render the install unavailable banner on a regular screen', () => {
        renderComponent({
          copilotApp: true,
          freeInstall: true,
          planInfoOverride: {isRegularEmuUser: true},
        })

        expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
      })
    })

    describe('When the marketplace_free_install flag is disabled', () => {
      it('Does not render the install unavailable banner', () => {
        renderComponent({copilotApp: true, planInfoOverride: {isRegularEmuUser: true}, isMobile: true})

        expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the app is not a Copilot app', () => {
    it('Does not render the works with section', () => {
      renderComponent()

      expect(screen.queryByTestId('apps-works-with')).not.toBeInTheDocument()
    })

    it('Does not render the install unavailable banner', () => {
      renderComponent({freeInstall: true, planInfoOverride: {isRegularEmuUser: true}, isMobile: true})

      expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
    })
  })
})
