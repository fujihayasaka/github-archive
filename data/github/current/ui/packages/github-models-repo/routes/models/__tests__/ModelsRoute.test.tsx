import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {getModelsRoutePayload} from '../../../test-utils/mock-data'
import {ModelsRoute} from '../ModelsRoute'

test('Renders the Models route', () => {
  const appPayload = getModelsRoutePayload()
  render(<ModelsRoute />, {
    appPayload,
  })

  expect(screen.getByRole('heading', {level: 2, name: 'Models'})).toBeInTheDocument()
})
