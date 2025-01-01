import {render} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {ModelsIndexRoute, docsUrl, feedbackUrl} from '../ModelsIndexRoute'
import {mockModel} from '../../playground/__tests__/mocks'
import {ModelUrlHelper} from '../../../utils/model-url-helper'
import {mockModelsIndexRoutePayload} from './mocks'

describe('ModelsIndexRoute', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders the playground', () => {
    const payload = mockModelsIndexRoutePayload()

    const {container} = render(<ModelsIndexRoute />, {routePayload: payload})

    expect(within(container).getByRole('textbox', {name: 'Search Marketplace'})).toBeInTheDocument()
    expect(
      within(container).queryByRole('link', {name: 'Get early access to our playground for models'}),
    ).not.toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'Models', level: 2})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
    expect(within(container).getByTestId('models-index-filters')).toBeInTheDocument()
    const modelHeading = within(container).getByRole('heading', {name: mockModel.friendly_name, level: 3})
    expect(modelHeading).toBeInTheDocument()
    expect(within(modelHeading).getByRole('link', {name: mockModel.friendly_name})).toHaveAttribute(
      'href',
      ModelUrlHelper.modelUrl(mockModel),
    )
    expect(within(container).getByRole('link', {name: 'Learn more'})).toHaveAttribute('href', docsUrl)
  })
})
