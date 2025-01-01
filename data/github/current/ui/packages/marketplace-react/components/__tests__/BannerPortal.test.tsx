import {BannerPortal} from '../BannerPortal'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

describe('BannerPortal', () => {
  afterEach(() => {
    // Clean up the flash container after each test
    // eslint-disable-next-line testing-library/no-node-access
    const flashContainer = document.getElementById('js-flash-container')
    if (flashContainer) {
      document.body.removeChild(flashContainer)
    }
  })

  test('Renders banner when there is a js-flash-container', () => {
    // Add the flash container to the document body
    const flashContainer = document.createElement('div')
    flashContainer.id = 'js-flash-container'
    document.body.appendChild(flashContainer)

    render(<BannerPortal message="Banner message" variant="critical" onDismiss={() => {}} />)

    expect(screen.getByText('Banner message')).toBeInTheDocument()
  })

  test('Does not render when there is no js-flash-container', () => {
    render(<BannerPortal message="Banner message" variant="critical" onDismiss={() => {}} />)

    expect(screen.queryByText('Banner message')).not.toBeInTheDocument()
  })
})
