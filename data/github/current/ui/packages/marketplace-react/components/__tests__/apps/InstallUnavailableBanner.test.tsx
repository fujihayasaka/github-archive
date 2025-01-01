import {screen} from '@testing-library/react'
import InstallUnavailableBanner from '../../apps/InstallUnavailableBanner'
import {mockPlanInfo} from '../../../test-utils/mock-data'
import {render} from '@github-ui/react-core/test-utils'

function renderComponent({
  isRegularEmuUser = true,
  emuOwnerButNotAdmin = false,
  viewerHasPurchased = false,
  viewerHasPurchasedForAllOrganizations = false,
} = {}) {
  return render(
    <InstallUnavailableBanner
      planInfo={mockPlanInfo({
        isRegularEmuUser,
        emuOwnerButNotAdmin,
        viewerHasPurchased,
        viewerHasPurchasedForAllOrganizations,
      })}
    />,
  )
}

describe('InstallUnavailableBanner', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })
  it('Renders the banner if install unavailable', () => {
    renderComponent()

    expect(screen.getByText('Install unavailable')).toBeInTheDocument()
  })

  it('Does not render the banner if install is available', () => {
    renderComponent({isRegularEmuUser: false})

    expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
  })

  it('Does not render the banner if the user has fully purchased the app', () => {
    renderComponent({viewerHasPurchased: true, viewerHasPurchasedForAllOrganizations: true})

    expect(screen.queryByText('Install unavailable')).not.toBeInTheDocument()
  })

  it('Renders banner for regular EMU user', () => {
    renderComponent({isRegularEmuUser: true, emuOwnerButNotAdmin: false})

    expect(
      screen.getByText(
        'Only enterprise administrators and organization admins can purchase applications from the marketplace.',
      ),
    ).toBeInTheDocument()
  })

  it('Renders banner for EMU owner but not admin', () => {
    renderComponent({isRegularEmuUser: false, emuOwnerButNotAdmin: true})

    expect(screen.getByText('Only enterprise admins are able to install paid Marketplace plans.')).toBeInTheDocument()
  })
})
