import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {NavigationContextProvider} from '@github-ui/licensing-common/contexts/NavigationContext'
import {CSVDownloader} from '../CSVDownloader'
import {getCSVDownloaderProps, skus} from '../../test-utils/mock-data'

const renderCSVDownloader = (overrideProps = {}, stafftools = false) => {
  return render(
    <NavigationContextProvider
      enterpriseContactUrl={'/enterprise-contact-url'}
      isStafftools={stafftools}
      slug="test-co"
      isTeams={false}
    >
      <CSVDownloader {...getCSVDownloaderProps()} {...overrideProps} />
    </NavigationContextProvider>,
  )
}

describe('CSVDownloader Component', () => {
  const baseUrl = '/enterprises/test-co/enterprise_licensing/download_active_committers'

  test('renders nothing when no SKUs are available', () => {
    renderCSVDownloader({skus: []})

    expect(screen.queryByTestId('csv-downloader-button')).not.toBeInTheDocument()
    expect(screen.queryByTestId('csv-downloader-menu')).not.toBeInTheDocument()
  })

  test('renders a single button when only one SKU is available', () => {
    renderCSVDownloader({skus: skus.filter(sku => sku.sku === 'bundled')})

    const button = screen.getByTestId('csv-downloader-button')
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('href', baseUrl)
    expect(button).toHaveTextContent('Download CSV report')
  })

  test('renders a dropdown menu when multiple SKUs are available', async () => {
    const {user} = renderCSVDownloader({skus: skus.filter(sku => sku.sku !== 'bundled')})

    // Check that the menu button is rendered
    const menuButton = screen.getByRole('button', {name: /Download CSV report/i})
    expect(menuButton).toBeInTheDocument()

    // Open the menu
    await user.click(menuButton)

    const secretProtectionLinkElem = screen.getByTestId('csv-download-secret-protection')
    const codeSecurityLinkElem = screen.getByTestId('csv-download-code-security')

    // Check that the menu options are rendered
    expect(secretProtectionLinkElem).toBeInTheDocument()
    expect(codeSecurityLinkElem).toBeInTheDocument()

    expect(secretProtectionLinkElem).toHaveAttribute('href', `${baseUrl}?sku=secret-protection`)
    expect(codeSecurityLinkElem).toHaveAttribute('href', `${baseUrl}?sku=code-security`)

    expect(secretProtectionLinkElem).toHaveTextContent('Secret Protection')
    expect(codeSecurityLinkElem).toHaveTextContent('Code Security')
  })
})
