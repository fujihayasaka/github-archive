import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import SidebarInfo from '../SidebarInfo'
import {mockModel as baseMockModel} from '../../../routes/playground/__tests__/mocks'

describe('SidebarInfo', () => {
  test('renders non-static model', () => {
    const mockModel = Object.assign({}, baseMockModel)
    mockModel.max_input_tokens = 123000
    mockModel.max_output_tokens = 456000
    mockModel.rate_limit_tier = 'big'
    const tag1 = 'NeatoTag'
    const tag2 = 'ASecondWorthyTag'
    mockModel.tags = [tag1, tag2]
    mockModel.task = 'some_kind_of_task'
    mockModel.supported_languages = ['fr', 'es']

    const {container} = render(<SidebarInfo model={mockModel} />)

    expect(within(container).getByTestId('sidebar-info')).toBeInTheDocument()
    expect(within(container).getByRole('heading', {name: 'About', level: 3})).toBeInTheDocument()
    expect(within(container).getByTestId('languages')).toHaveTextContent('French, and Spanish')
    expect(within(container).queryByRole('button', {name: 'Reveal all languages'})).not.toBeInTheDocument()
    expect(within(container).getByTestId('summary')).toHaveTextContent(mockModel.summary || '')

    const modelDetailsEl = within(container).getByTestId('model-details')
    expect(modelDetailsEl).toBeInTheDocument()
    expect(within(modelDetailsEl).getByTestId('context')).toHaveTextContent('123k input · 456k output')
    expect(within(modelDetailsEl).getByTestId('training-date')).toHaveTextContent(mockModel.training_data_date!)
    expect(within(modelDetailsEl).getByTestId('rate-limit-tier')).toHaveTextContent('Big')
    expect(within(modelDetailsEl).getByRole('link', {name: 'Azure support site'})).toBeInTheDocument()

    const tagsEl = within(container).getByTestId('tags-section')
    expect(tagsEl).toBeInTheDocument()
    expect(within(tagsEl).getByRole('link', {name: tag1})).toBeInTheDocument()
    expect(within(tagsEl).getByRole('link', {name: tag2})).toBeInTheDocument()
    expect(within(tagsEl).getByRole('link', {name: mockModel.task})).toBeInTheDocument()
  })

  test('collapses languages section when there are a lot', async () => {
    const mockModel = Object.assign({}, baseMockModel)
    mockModel.supported_languages = ['en', 'zh', 'fr', 'ja', 'es', 'de', 'it', 'pt', 'ru', 'ko', 'hy', 'ka', 'id']

    const {container, user} = render(<SidebarInfo model={mockModel} />)

    expect(within(container).getByTestId('sidebar-info')).toBeInTheDocument()
    expect(within(container).getByTestId('languages')).toHaveTextContent(
      'English, Chinese, French, Japanese, Spanish, German, Italian, Portuguese, Russian, Korean, Armenian, Georgian',
    )
    const toggleLanguagesButton = within(container).getByRole('button', {name: 'Reveal all languages'})
    expect(toggleLanguagesButton).toBeInTheDocument()

    await user.click(toggleLanguagesButton)

    expect(within(container).getByTestId('languages')).toHaveTextContent(
      'English, Chinese, French, Japanese, Spanish, German, Italian, Portuguese, Russian, Korean, Armenian, Georgian, and Indonesian',
    )
  })
})
