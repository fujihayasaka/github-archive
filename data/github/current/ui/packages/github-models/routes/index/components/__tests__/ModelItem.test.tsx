import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../../playground/__tests__/mocks'
import ModelItem from '../ModelItem'

describe('ModelItem', () => {
  test('renders non-featured model when isFeatured is false', () => {
    render(<ModelItem model={mockModel} isFeatured={false} />)

    expect(screen.getByTestId('marketplace-item')).toHaveClass('gap-3 p-3')
    expect(screen.getByRole('img')).toHaveAttribute('src', `data:image/svg+xml;base64,${mockModel.light_mode_icon}`)
    expect(screen.getByText('My Test Model')).toHaveAttribute(
      'href',
      `/marketplace/models/${mockModel.registry}/${mockModel.name}`,
    )
    expect(screen.getByText('Model')).toBeInTheDocument()
    expect(screen.getByText('Use this model to do stuff.')).toBeInTheDocument()
  })

  test('renders publisher of the model when there is no summary', () => {
    const clonedMockModel = {...mockModel, summary: undefined, publisher: 'ai21labs'}
    render(<ModelItem model={clonedMockModel} isFeatured={false} />)

    expect(screen.queryByText('Use this model to do stuff.')).not.toBeInTheDocument()
    expect(screen.getByText('AI21 Labs')).toBeInTheDocument()
  })

  test('renders featured model when isFeatured is true', () => {
    const model = Object.assign({}, mockModel, {publisher: 'openai'})

    render(<ModelItem model={model} isFeatured />)

    expect(screen.getByTestId('marketplace-item')).toHaveClass('flex-column flex-items-center p-4')
    expect(screen.getByRole('img')).toHaveAttribute('src', `data:image/svg+xml;base64,${model.light_mode_icon}`)
    expect(screen.getByTestId('featured-item')).toBeInTheDocument()
    expect(screen.getByText('My Test Model')).toHaveAttribute(
      'href',
      `/marketplace/models/${model.registry}/${model.name}`,
    )
    expect(screen.getByText('by Azure OpenAI Service')).toBeInTheDocument()
    expect(screen.getByText('Use this model to do stuff.')).toBeInTheDocument()
    expect(screen.getByTestId('listing-type-label')).toHaveTextContent('Model')
    expect(screen.getByText('Model')).toBeInTheDocument()
  })

  test('renders logo at 36px by 36px for AI21 Labs models', () => {
    const clonedMockModel = {...mockModel, model_family: 'AI21 Labs'}
    render(<ModelItem model={clonedMockModel} isFeatured />)
    expect(screen.getByTestId('logo-image')).toHaveAttribute('style', '--avatarSize-regular: 36px;')
  })

  test('renders logo without customized styles for non-AI21 Labs models', () => {
    render(<ModelItem model={mockModel} isFeatured />)
    expect(screen.getByTestId('logo-image')).not.toHaveAttribute('style', 'width: 36px; height: 36px;')
  })
})
