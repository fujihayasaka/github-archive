import type {SafeHTMLString} from '@github-ui/safe-html'
import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {Readme} from '../Readme'
import {mockShowModelPayload} from './mocks'
import {mockModel} from '../../../playground/__tests__/mocks'
import {PUBLISHER} from '../../../../utils/normalize-model-strings'

describe('Readme', () => {
  test('renders with header image for recognized model family', () => {
    const model = Object.assign(mockModel, {model_family: PUBLISHER.Cohere, publisher: PUBLISHER.Cohere})
    const readmeParagraphs = [
      'How doth the little crocodile',
      'Improve his shining tail',
      'And pour the waters of the Nile',
      'On every golden scale!',
    ]
    const readme = readmeParagraphs.map(text => `<p>${text}</p>`).join('')
    const payload = mockShowModelPayload({model, modelReadme: readme as SafeHTMLString})

    const {container} = render(<Readme />, {routePayload: payload})

    const heroEl = within(container).getByTestId('readme-hero')
    expect(heroEl).toBeInTheDocument()
    expect(within(heroEl).getByRole('img', {name: 'cohere'})).toBeInTheDocument()
    const readmeContentEl = within(container).getByTestId('readme-content')
    expect(readmeContentEl).toBeInTheDocument()
    for (const text of readmeParagraphs) {
      expect(within(readmeContentEl).getByText(text)).toBeInTheDocument()
    }
  })

  test('renders without header image for unrecognized model family', () => {
    const model = Object.assign(mockModel, {model_family: 'testfoo', publisher: 'Some Publisher Name'})
    const readme = '<h3>A headline!</h3><p>Some readme content</p>'
    const payload = mockShowModelPayload({model, modelReadme: readme as SafeHTMLString})

    const {container} = render(<Readme />, {routePayload: payload})

    expect(within(container).queryByTestId('readme-hero')).not.toBeInTheDocument()
    const readmeContentEl = within(container).getByTestId('readme-content')
    expect(readmeContentEl).toBeInTheDocument()
    expect(within(readmeContentEl).getByRole('heading', {name: 'A headline!', level: 3})).toBeInTheDocument()
    expect(within(readmeContentEl).getByRole('paragraph')).toHaveTextContent('Some readme content')
  })
})
