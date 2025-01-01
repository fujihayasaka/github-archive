import ModelsAvatar from '../ModelsAvatar'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../routes/playground/__tests__/mocks'

describe('ModelsAvatar', () => {
  test('renders with the correct alt tag', () => {
    render(<ModelsAvatar model={mockModel} />)
    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})

    expect(imageElement).toBeInTheDocument()
  })

  test('renders with the correct light mode icon', () => {
    setColorMode('light')
    render(<ModelsAvatar model={mockModel} />)
    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(`data:image/svg+xml;base64,${mockModel.light_mode_icon}`)
  })

  test('defaults to the light mode icon', () => {
    setColorMode('auto')
    render(<ModelsAvatar model={mockModel} />)
    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(`data:image/svg+xml;base64,${mockModel.light_mode_icon}`)
  })

  test('renders with the correct dark mode icon', () => {
    setColorMode('dark')
    render(<ModelsAvatar model={mockModel} />)
    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(`data:image/svg+xml;base64,${mockModel.dark_mode_icon}`)
  })

  test('renders the logo url if the matching icon is not found', () => {
    const mockModelWithoutNightMode = Object.assign({}, mockModel)
    mockModelWithoutNightMode.dark_mode_icon = ''

    setColorMode('dark')

    render(<ModelsAvatar model={mockModelWithoutNightMode} />)
    const imageElement = screen.getByRole('img', {name: `${mockModelWithoutNightMode.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(`${mockModelWithoutNightMode.logo_url}`)
  })

  test('does not break if there is no logo_url to fall back to', () => {
    const mockModelWithoutFallback = Object.assign({}, mockModel)
    mockModelWithoutFallback.dark_mode_icon = ''
    mockModelWithoutFallback.logo_url = ''

    setColorMode('dark')

    render(<ModelsAvatar model={mockModelWithoutFallback} />)
    const imageElement = screen.getByRole('img', {name: `${mockModelWithoutFallback.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual('')
  })
})

function setColorMode(mode: 'light' | 'dark' | 'auto' | '') {
  const {documentElement} = document
  if (mode === '') {
    documentElement.removeAttribute('data-color-mode')
  } else if (mode === 'light') {
    documentElement.setAttribute('data-color-mode', 'light')
  } else {
    documentElement.setAttribute('data-color-mode', mode)
  }
}
