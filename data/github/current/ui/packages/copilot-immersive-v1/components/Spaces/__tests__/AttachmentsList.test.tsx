import type {CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {noop} from '@github-ui/noop'
import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'

import {AttachmentsList} from '../AttachmentsList'

describe('AttachmentsList', () => {
  it('handles empty attachments list', () => {
    const attachments: CustomCopilotResource[] = []

    render(<AttachmentsList attachments={attachments} onTextFileClick={noop} />)

    expect(screen.queryByRole('listitem')).not.toBeInTheDocument()
  })

  it('renders uploaded_text_file attachments', async () => {
    const attachment: CustomCopilotResource = {
      id: '1',
      type: 'uploaded_text_file',
      name: 'test-file.txt',
      copilotChatAttachmentId: 123,
      markedForDestroy: false,
    }

    const onClick = jest.fn()
    const {user} = render(<AttachmentsList attachments={[attachment]} onTextFileClick={onClick} />)

    const listItem = await screen.findByRole('listitem')
    expect(within(listItem).getByText('test-file.txt')).toBeInTheDocument()

    await user.click(within(listItem).getByRole('button'))
    expect(onClick).toHaveBeenCalledWith(attachment)
  })
})
