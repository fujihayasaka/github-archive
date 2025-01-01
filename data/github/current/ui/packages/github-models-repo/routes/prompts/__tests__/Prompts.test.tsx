import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getModelRepoPromptsAppPayload, getModelRepoPromptsRoutePayload} from '../../../test-utils/mock-data'
import {PromptsRoute} from '../PromptsRoute'

describe('Prompts route', () => {
  test('renders with cta when user can edit', () => {
    const appPayload = getModelRepoPromptsAppPayload({canEdit: true})
    const routePayload = getModelRepoPromptsRoutePayload()

    render(<PromptsRoute />, {appPayload, routePayload})

    expect(screen.getByRole('heading', {level: 2, name: 'Prompts'})).toBeInTheDocument()
    expect(screen.getByText('New prompt')).toBeInTheDocument()
  })

  test('renders without cta when user cannot edit', () => {
    const appPayload = getModelRepoPromptsAppPayload({canEdit: false})
    const routePayload = getModelRepoPromptsRoutePayload()

    render(<PromptsRoute />, {appPayload, routePayload})

    expect(screen.getByRole('heading', {level: 2, name: 'Prompts'})).toBeInTheDocument()
    expect(screen.queryByText('New prompt')).not.toBeInTheDocument()
  })
})
