import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getModelRepoPromptsAppPayload, getModelRepoPromptsRoutePayload} from '../../../test-utils/mock-data'
import {ComparisonsRoute} from '../ComparisonsRoute'

describe('Comparisons route', () => {
  test('renders', () => {
    const appPayload = getModelRepoPromptsAppPayload()
    const routePayload = getModelRepoPromptsRoutePayload()

    render(<ComparisonsRoute />, {appPayload, routePayload})

    expect(screen.getByRole('heading', {level: 2, name: 'Comparisons'})).toBeInTheDocument()
  })
})
