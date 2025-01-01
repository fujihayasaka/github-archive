import {PublisherAvatar} from '../PublisherAvatar'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../routes/playground/__tests__/mocks'

describe('PublisherAvatar', () => {
  test('renders with the correct alt tag and uses logo URL', () => {
    render(
      <PublisherAvatar
        logoUrl="https://example.com/logo.png"
        darkModeIcon={mockModel.dark_mode_icon}
        publisher="Open AI"
      />,
    )

    const imageElement = screen.getByRole('img', {name: 'Open AI logo'})
    expect(imageElement).toBeInTheDocument()
    expect(imageElement.getAttribute('src')).toEqual('https://example.com/logo.png')
  })

  test('renders with the correct dark mode icon for an AI21 Labs model', () => {
    render(
      <PublisherAvatar logoUrl={mockModel.logo_url} darkModeIcon={mockModel.dark_mode_icon} publisher="AI21 Labs" />,
    )

    const imageElement = screen.getByRole('img', {name: 'AI21 Labs logo'})
    expect(imageElement.getAttribute('src')).toEqual(`data:image/svg+xml;base64,${mockModel.dark_mode_icon}`)
  })

  test('renders the empty icon when AI21 Labs models do not have the dark mode icon', () => {
    render(<PublisherAvatar logoUrl={mockModel.logo_url} darkModeIcon="" publisher="AI21 Labs" />)

    const imageElement = screen.getByRole('img', {name: 'AI21 Labs logo'})
    expect(imageElement.getAttribute('src')).toEqual('')
  })

  test('renders the dark mode icon when the logo url is empty', () => {
    render(<PublisherAvatar logoUrl="" darkModeIcon={mockModel.dark_mode_icon} publisher={mockModel.publisher} />)

    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})
    expect(imageElement.getAttribute('src')).toEqual(`data:image/svg+xml;base64,${mockModel.dark_mode_icon}`)
  })

  test('does not break if there is neither logo_url nor dark mode icon to fall back to', () => {
    render(<PublisherAvatar logoUrl={null} darkModeIcon="" publisher={mockModel.publisher} />)

    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})
    expect(imageElement.getAttribute('src')).toEqual('')
  })
})
