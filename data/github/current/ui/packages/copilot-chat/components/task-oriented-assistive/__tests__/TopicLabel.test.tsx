import {render, screen} from '@testing-library/react'

import {getRepositoryMock} from '../../../test-utils/mock-data'
import type {CopilotChatRepo} from '../../../utils/copilot-chat-types'
import {TopicLabel} from '../TopicLabel'

describe('TopicLabel', () => {
  it('renders nothing when topic is undefined', () => {
    const {container} = render(<TopicLabel />)
    expect(container).toBeEmptyDOMElement()
  })

  it('renders the topic name and icon when topic is provided', () => {
    const topic: CopilotChatRepo = {
      ...getRepositoryMock(),
      name: 'test-repo',
      ownerLogin: 'test-owner',
    }
    render(<TopicLabel topic={topic} />)

    expect(screen.getByText('test-owner/test-repo')).toBeInTheDocument()
  })
})
