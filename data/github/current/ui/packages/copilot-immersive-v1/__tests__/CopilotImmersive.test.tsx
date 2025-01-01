import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {CopilotImmersive} from '../routes/CopilotImmersive'
import {getCopilotImmersiveAppPayload} from '../test-utils/mock-data'

beforeEach(() => {
  jest.clearAllMocks()
  window.localStorage.clear()
  // We utilize service workers to fuzy search references in Copilot Chat
  // when they are not available we show a warning to the user.
  // Workers are not available in JSDOM so we need to mock the console.warn.
  jest.spyOn(console, 'warn').mockImplementation()
})

test('Renders the CopilotImmersive when copilotChatSettingEnabled is true', async () => {
  const appPayload = getCopilotImmersiveAppPayload()
  appPayload.copilotChatSettingEnabled = true

  render(<CopilotImmersive />, {
    appPayload,
  })

  await expect(screen.findByTestId('chat-layout')).resolves.toBeInTheDocument()
})
