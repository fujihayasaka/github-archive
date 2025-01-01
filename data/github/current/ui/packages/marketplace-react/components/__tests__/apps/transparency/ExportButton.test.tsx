import {mockAppListing} from '@github-ui/marketplace-common/mock-data'
import {ExportButton} from '../../../apps/transparency/ExportButton'
import {render} from '@github-ui/react-core/test-utils'
import {screen, act, waitFor} from '@testing-library/react'
import {verifiedFetch} from '@github-ui/verified-fetch'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

describe('ExportButton', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('Renders export button', () => {
    render(<ExportButton app={mockAppListing()} />)

    expect(screen.getByRole('button', {name: 'Export CSV'})).toBeInTheDocument()
  })

  it('Makes fetch request and downloads CSV when the button is clicked', async () => {
    const csvContent = 'column1,column2\nvalue1,value2'
    const blob = new Blob([csvContent], {type: 'text/csv'})
    const mockUrl = 'mock-url'

    mockVerifiedFetch.mockResolvedValue({
      status: 201,
      ok: true,
      blob: async () => blob,
    })

    global.URL.createObjectURL = jest.fn(() => mockUrl)
    global.URL.revokeObjectURL = jest.fn()

    render(<ExportButton app={mockAppListing({slug: 'test-app'})} />)

    act(() => {
      screen.getByRole('button', {name: 'Export CSV'}).click()
    })

    await waitFor(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith('/marketplace/test-app/transparency_report_exports', {
        method: 'POST',
        headers: {Accept: 'text/csv'},
      })
    })
    expect(URL.createObjectURL).toHaveBeenCalledWith(blob)
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(mockUrl)
  })

  it('Shows an error banner and does not download a csv when the fetch request fails', async () => {
    mockVerifiedFetch.mockResolvedValue({
      ok: false,
      status: 500,
    })

    // Add the flash container to the document body to ensure that the banner can be rendered
    const flashContainer = document.createElement('div')
    flashContainer.id = 'js-flash-container'
    document.body.appendChild(flashContainer)

    render(<ExportButton app={mockAppListing({slug: 'test-app'})} />)

    expect(screen.queryByText('An error occurred while exporting the CSV.')).not.toBeInTheDocument()

    act(() => {
      screen.getByRole('button', {name: 'Export CSV'}).click()
    })

    await waitFor(() => {
      expect(mockVerifiedFetch).toHaveBeenCalledWith('/marketplace/test-app/transparency_report_exports', {
        method: 'POST',
        headers: {Accept: 'text/csv'},
      })
    })
    expect(URL.createObjectURL).not.toHaveBeenCalled()
    expect(URL.revokeObjectURL).not.toHaveBeenCalled()
    expect(screen.getByText('An error occurred while exporting the CSV.')).toBeInTheDocument()
  })
})
