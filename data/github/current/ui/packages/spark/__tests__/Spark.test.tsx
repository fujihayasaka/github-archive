import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import Spark from '../routes/Spark'
import {getSparkPayload} from '../test-utils/mock-data'

jest.mock('@github-ui/feature-flags')

beforeEach(() => {
  jest.clearAllMocks()
  window.localStorage.clear()
  // We utilize service workers to fuzy search references in Copilot Chat
  // when they are not available we show a warning to the user.
  // Workers are not available in JSDOM so we need to mock the console.warn.
  jest.spyOn(console, 'warn').mockImplementation()
})

test('Renders the Spark', async () => {
  const appPayload = getSparkPayload()
  render(<Spark />, {
    appPayload,
  })

  await expect(screen.findByTestId('dashboard-layout')).resolves.toBeInTheDocument()
})
