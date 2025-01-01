import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {within} from '@testing-library/react'
import {fireFileDropEvent} from '../../__tests__/test-utils'
import {AttachmentDropzone} from '../AttachmentDropzone'
import {AttachmentsProvider} from '@github-ui/attachments'
import {MockFileAttachment, testFile} from '@github-ui/attachments/test-utils'

const useCreateAttachmentCallback = jest
  .fn((file: File) => new MockFileAttachment(file))
  .mockName('useCreateAttachment#callback')

jest.mock('../use-create-attachment', () => ({
  useCreateAttachment() {
    return useCreateAttachmentCallback
  },
}))

beforeEach(() => {
  jest.clearAllMocks()
})

describe('AttachmentDropzone', () => {
  test('calls the useCreateAttachment hook when a file is dropped', async () => {
    const {container} = render(<AttachmentDropzone enabled />)

    const el = within(container).getByTestId('playground-chat-attachment-dropzone')

    fireFileDropEvent([testFile()], el)

    expect(useCreateAttachmentCallback).toHaveBeenCalledTimes(1)
  })
})

function render(component: JSX.Element) {
  return htmlRender(<AttachmentsProvider>{component}</AttachmentsProvider>)
}
