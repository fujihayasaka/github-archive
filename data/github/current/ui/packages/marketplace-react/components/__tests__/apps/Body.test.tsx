import {Body} from '../../apps/Body'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {mockPlanInfo} from '../../../test-utils/mock-data'
import {useResponsiveValue} from '@primer/react'

jest.mock('@primer/react', () => ({
  ...jest.requireActual('@primer/react'),
  useResponsiveValue: jest.fn(),
}))
function mockIsDesktop(value: boolean) {
  ;(useResponsiveValue as jest.Mock).mockImplementation(() => value)
}

function renderComponent({copilotApp = false, search = '', isDesktop = true, planInfoOverride = {}} = {}) {
  mockIsDesktop(isDesktop)
  render(
    <Body
      app={mockAppListing({fullDescription: 'fullDescription', extendedDescription: 'extendedDescription', copilotApp})}
      screenshots={[
        {
          id: 1,
          src: 'example.com/screenshot1.png',
          altText: 'Screenshot 1',
        },
      ]}
      planInfo={mockPlanInfo(planInfoOverride)}
      supportedLanguages={['JavaScript', 'TypeScript']}
      permissionsData={[]}
    />,
    {search},
  )
}

describe('Body', () => {
  it('Renders tabs for the readme and transparency sections', () => {
    renderComponent()

    expect(screen.getByRole('link', {name: 'README'})).toHaveAttribute('href', '/?tab=readme')
    expect(screen.getByRole('link', {name: 'Transparency'})).toHaveAttribute('href', '/?tab=transparency')
  })

  it('Renders only the readme content when no tab has been selected', () => {
    renderComponent()

    expect(screen.getByTestId('readme-content')).toBeInTheDocument()
    expect(screen.getByText('fullDescription')).toBeInTheDocument()
    expect(screen.getByText('extendedDescription')).toBeInTheDocument()
    expect(screen.getByTestId('screenshot-carousel')).toBeInTheDocument()
    expect(screen.queryByTestId('transparency-section')).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'README'})).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', {name: 'Transparency'})).not.toHaveAttribute('aria-current', 'page')
  })

  it('Renders only the transparency section when the transparency tab has already been selected', () => {
    renderComponent({search: '?tab=transparency'})

    expect(screen.getByTestId('transparency-section')).toBeInTheDocument()
    expect(screen.queryByTestId('readme-content')).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Transparency'})).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', {name: 'README'})).not.toHaveAttribute('aria-current', 'page')
  })

  it('Renders only the readme content when the readme tab has already been selected', () => {
    renderComponent({search: '?tab=readme'})

    expect(screen.getByTestId('readme-content')).toBeInTheDocument()
    expect(screen.queryByTestId('transparency-section')).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'README'})).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', {name: 'Transparency'})).not.toHaveAttribute('aria-current', 'page')
  })

  it('Renders only the readme content when a non-existent tab has been selected', () => {
    renderComponent({search: '?tab=fake'})

    expect(screen.getByTestId('readme-content')).toBeInTheDocument()
    expect(screen.queryByTestId('transparency-section')).not.toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'README'})).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', {name: 'Transparency'})).not.toHaveAttribute('aria-current', 'page')
  })

  describe('When the app is a Copilot app', () => {
    it('Renders the Copilot listing requirement', () => {
      renderComponent({copilotApp: true})

      expect(screen.getByTestId('copilot-listing-requirement')).toBeInTheDocument()
    })

    it('Does not render plans and pricing section', () => {
      renderComponent({copilotApp: true})

      expect(screen.queryByText('Plans and pricing')).not.toBeInTheDocument()
    })

    it('Renders the terms of service', () => {
      renderComponent({copilotApp: true})

      expect(
        screen.getByText(/amazing app is provided by a third-party and is governed by separate , , and/i),
      ).toBeInTheDocument()
    })

    describe('When the app is viewed on a regular screen', () => {
      it('Renders the install unavailable banner', () => {
        renderComponent({copilotApp: true, planInfoOverride: {isRegularEmuUser: true}})

        expect(screen.getByText('Install unavailable')).toBeInTheDocument()
      })
    })

    describe('When the app is viewed on a narrow screen', () => {
      it('Does not render the install unavailable banner', () => {
        renderComponent({
          copilotApp: true,
          planInfoOverride: {isRegularEmuUser: true},
          isDesktop: false,
        })

        expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
      })
    })
  })

  describe('When the app is not a Copilot app', () => {
    it('Does not render the Copilot listing requirement', () => {
      renderComponent()

      expect(screen.queryByTestId('copilot-listing-requirement')).not.toBeInTheDocument()
    })

    it('Renders the plans and pricing section', () => {
      renderComponent()

      expect(screen.getByText('Plans and pricing')).toBeInTheDocument()
    })

    it('Does not render the install unavailable banner', () => {
      renderComponent({planInfoOverride: {isRegularEmuUser: true}})

      expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
    })
  })

  it('Renders the languages section', () => {
    renderComponent()

    expect(screen.getByTestId('languages')).toBeInTheDocument()
  })

  it('Renders the pricing plans section', () => {
    renderComponent()

    expect(screen.getByTestId('pricing')).toBeInTheDocument()
  })
})
