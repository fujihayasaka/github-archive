import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import type {CopilotAnnotations} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CodeInsightsDialog} from '../extensions/code-blocks/CodeInsightsDialog/CodeInsightsDialog'

const userEvent = setupUserEvent()

describe('CodeInsightsDialog', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders a Dialog', async () => {
    const onClose = jest.fn()

    const publicCodeReferences: CopilotAnnotations['PublicCodeReference'] = [
      {
        startOffset: 0,
        endOffset: 0,
        details: {
          sourceURL: 'https://github.com/github/github/blob/main/LICENSE',
          license: 'MIT',
          language: 'JavaScript',
        },
      },
    ]

    const codeVulnerabilities: CopilotAnnotations['CodeVulnerability'] = [
      {
        startOffset: 0,
        endOffset: 0,
        details: {
          description: 'Sample Vulnerability',
          type: 'Security',
          uiDescription: 'Sample UI Description',
          uiType: 'Sample UI Type',
        },
      },
    ]

    render(
      <CodeInsightsDialog
        publicCodeReferences={publicCodeReferences}
        codeVulnerabilities={codeVulnerabilities}
        onClose={onClose}
      />,
    )

    await userEvent.click(await screen.findByLabelText('Close'))
    expect(onClose).toHaveBeenCalled()
  })
})
