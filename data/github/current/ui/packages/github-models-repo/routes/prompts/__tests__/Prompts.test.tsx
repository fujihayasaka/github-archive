import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getModelsRoutePayload} from '../../../test-utils/mock-data'
import {PromptsRoute, type ModelPromptsRepoPayload} from '../PromptsRoute'

describe('Prompts route', () => {
  test('renders with cta when user can edit', () => {
    const appPayload: ModelPromptsRepoPayload = {
      ...getModelsRoutePayload(),
      canEdit: true,
    }
    render(<PromptsRoute />, {
      appPayload,
    })

    expect(screen.getAllByRole('heading', {level: 2, name: 'Prompts'})).toHaveLength(2)
    expect(screen.getByText('New prompt')).toBeInTheDocument()
  })

  test('renders without cta when user cannot edit', () => {
    const appPayload: ModelPromptsRepoPayload = {
      ...getModelsRoutePayload(),
      canEdit: false,
    }
    render(<PromptsRoute />, {
      appPayload,
    })

    expect(screen.getAllByRole('heading', {level: 2, name: 'Prompts'})).toHaveLength(2)
    expect(screen.queryByText('New prompt')).not.toBeInTheDocument()
  })
})
