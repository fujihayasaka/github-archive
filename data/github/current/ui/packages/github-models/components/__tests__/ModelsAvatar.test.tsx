import {ModelsAvatar} from '../ModelsAvatar'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../routes/playground/__tests__/mocks'

describe('ModelsAvatar', () => {
  test('renders with the correct alt tag', () => {
    render(<ModelsAvatar model={mockModel} />)
    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})

    expect(imageElement).toBeInTheDocument()
  })

  test('renders with the correct dark mode icon for an AI21 Labs model', () => {
    const aI21LabsModel = {...mockModel, publisher: 'AI21 Labs'}
    render(<ModelsAvatar model={aI21LabsModel} />)
    const imageElement = screen.getByRole('img', {name: `${aI21LabsModel.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(`data:image/svg+xml;base64,${aI21LabsModel.dark_mode_icon}`)
  })

  test('renders the empty icon when AI21 Labs models do not have the dark mode icon', () => {
    const aI21LabsModel = {...mockModel, publisher: 'AI21 Labs', dark_mode_icon: ''}
    render(<ModelsAvatar model={aI21LabsModel} />)
    const imageElement = screen.getByRole('img', {name: `${aI21LabsModel.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual('')
  })

  test('renders the logo url for other models', () => {
    render(<ModelsAvatar model={mockModel} />)
    const imageElement = screen.getByRole('img', {name: `${mockModel.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(`${mockModel.logo_url}`)
  })

  test('renders the dark mode icon when the logo url is empty', () => {
    const mockModelWithoutFallback = {...mockModel, logo_url: ''}

    render(<ModelsAvatar model={mockModelWithoutFallback} />)
    const imageElement = screen.getByRole('img', {name: `${mockModelWithoutFallback.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual(
      `data:image/svg+xml;base64,${mockModelWithoutFallback.dark_mode_icon}`,
    )
  })

  test('does not break if there is neither logo_url nor dark mode icon to fall back to', () => {
    const mockModelWithoutFallback = {...mockModel, logo_url: null, dark_mode_icon: ''}

    render(<ModelsAvatar model={mockModelWithoutFallback} />)
    const imageElement = screen.getByRole('img', {name: `${mockModelWithoutFallback.publisher} logo`})

    expect(imageElement.getAttribute('src')).toEqual('')
  })
})
