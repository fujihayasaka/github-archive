import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import Spark from '../routes/Spark'
import {getSparkPayload} from '../test-utils/mock-data'

// Mock codespaces-lsp which is causing the error with RemoteProvider
jest.mock('@github/codespaces-lsp', () => ({
  RemoteProvider: class MockRemoteProvider {
    constructor() {}
    createSshChannel() {}
    refillCache() {}
  },
}))

// Mock the problematic dependencies
jest.mock('@github-ui/copilot-loops', () => ({
  PipesPlugin: class MockPipesPlugin {
    constructor() {}
  },
}))

jest.mock('@github-ui/copilot-chat/utils/copilot-feature-flags', () => ({
  copilotFeatureFlags: {
    pipesPlugin: false,
    immersiveIssuePreview: false,
    draftIssueUI: false,
    workbenchUserLimits: false, // Add this to avoid WorkbenchBanner issues
  },
}))
jest.mock('@github-ui/workbench/contexts/UserPromptContext', () => ({
  useUserPromptContext: jest.fn().mockReturnValue({}),
}))

beforeEach(() => {
  jest.clearAllMocks()
  window.localStorage.clear()
  // Workers aren't available in JSDOM so we stub out console.warn
  jest.spyOn(console, 'warn').mockImplementation(() => {})
})

test('Renders the Spark dashboard layout', async () => {
  const appPayload = getSparkPayload()
  render(<Spark />, {appPayload})

  const dashboard = await screen.findByTestId('dashboard-layout')
  expect(dashboard).toBeInTheDocument()
})
