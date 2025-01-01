import {CopilotTextAttacher} from '@github-ui/copilot-chat/utils/copilot-text-attacher'
import {UploadableFileAttachment} from '@github-ui/copilot-chat/utils/uploadable-file-attachment'
import type {CustomCopilotUploadedTextFileResource} from '@github-ui/custom-copilots/types'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {FileUploadInput} from '../FileUploadInput'

jest.mock('@github-ui/copilot-chat/utils/copilot-text-attacher')
jest.mock('@github-ui/copilot-chat/utils/uploadable-file-attachment')

describe('FileUploadInput', () => {
  const mockOnResourcesAdded = jest.fn()
  const mockValidateCopilotSpaceResource = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()

    jest.mocked(CopilotTextAttacher).getAttachmentSizeLimit.mockReturnValue(500 * 1024)
    jest.mocked(CopilotTextAttacher).getTextFileExtensions.mockReturnValue('.txt,.js,.md')
    jest.mocked(CopilotTextAttacher).isAttachable.mockResolvedValue(true)
    jest.mocked(UploadableFileAttachment).mockImplementation(
      () =>
        ({
          assetId: jest.fn().mockResolvedValue(123),
        }) as Pick<UploadableFileAttachment, 'assetId'> as UploadableFileAttachment,
    )

    mockValidateCopilotSpaceResource.mockImplementation(({resources}) => {
      const result: Record<string, number> = {}
      for (const resource of resources) {
        result[resource.id] = 10
      }
      return Promise.resolve(result)
    })
  })

  it('renders a hidden file input', () => {
    render(
      <FileUploadInput
        onResourcesAdded={mockOnResourcesAdded}
        validateCopilotSpaceResource={mockValidateCopilotSpaceResource}
      />,
    )

    const fileInput = screen.getByTestId('file-upload-input')
    expect(fileInput).toBeInTheDocument()
    expect(fileInput).toHaveAttribute('type', 'file')
    expect(fileInput).toHaveAttribute('accept', '.txt,.js,.md')
    expect(fileInput).toHaveAttribute('multiple')
    expect(fileInput).toHaveStyle({display: 'none'})
  })

  it('processes valid files and creates uploaded text file resources', async () => {
    const file = new File(['console.log("test")'], 'test.js', {type: 'text/javascript'})

    const {user} = render(
      <FileUploadInput
        onResourcesAdded={mockOnResourcesAdded}
        validateCopilotSpaceResource={mockValidateCopilotSpaceResource}
      />,
    )

    const fileInput = screen.getByTestId<HTMLInputElement>('file-upload-input')

    // Simulate file selection
    await user.upload(fileInput, file)

    // Verify the resource was created correctly
    expect(mockOnResourcesAdded).toHaveBeenCalledWith([
      {
        id: expect.any(String), // ID is generated, so we use expect.any
        type: 'uploaded_text_file',
        name: 'test.js',
        copilotChatAttachmentId: 123,
        markedForDestroy: false,
        sizePercentage: 10,
      } satisfies CustomCopilotUploadedTextFileResource,
    ])

    // File input value should be reset
    expect(fileInput.value).toBe('')
  })

  it('rejects files that exceed size limit', async () => {
    const largeFile = new File(['x'.repeat(600 * 1024)], 'large.txt', {type: 'text/plain'})

    const {user} = render(
      <FileUploadInput
        onResourcesAdded={mockOnResourcesAdded}
        validateCopilotSpaceResource={mockValidateCopilotSpaceResource}
      />,
    )

    const fileInput = screen.getByTestId('file-upload-input')

    // Simulate file selection
    await user.upload(fileInput, largeFile)

    expect(mockOnResourcesAdded).not.toHaveBeenCalled()
  })

  it('rejects non-attachable files', async () => {
    jest.mocked(CopilotTextAttacher).isAttachable.mockResolvedValue(false)
    const nonTextFile = new File(['binary data'], 'image.png', {type: 'image/png'})

    const {user} = render(
      <FileUploadInput
        onResourcesAdded={mockOnResourcesAdded}
        validateCopilotSpaceResource={mockValidateCopilotSpaceResource}
      />,
    )

    const fileInput = screen.getByTestId('file-upload-input')

    // Simulate file selection
    await user.upload(fileInput, nonTextFile)

    expect(mockOnResourcesAdded).not.toHaveBeenCalled()
  })
})
