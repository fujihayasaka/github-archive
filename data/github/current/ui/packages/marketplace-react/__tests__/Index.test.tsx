import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {Index} from '../routes/Index'
import {getIndexRoutePayload} from '@github-ui/marketplace-common/mock-data'

describe('Index', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })
  test('Renders the Index page', async () => {
    // mock console error since rendering search field with data
    // causes error to be printed
    jest.spyOn(console, 'error').mockImplementation(() => {})

    const routePayload = getIndexRoutePayload()
    render(<Index />, {
      routePayload,
    })
    expect(screen.getByRole('heading', {level: 1})).toHaveTextContent('Enhance your workflow with extensions')
  })
})
