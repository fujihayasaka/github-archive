import {mockFetch} from '@github-ui/mock-fetch'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {CreateCopilotSpace} from '../CreateCopilotSpace'

const userEvent = setupUserEvent()

describe('CreateCopilotSpace', () => {
  const onDismiss = jest.fn()
  const onCreate = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders correctly when open', () => {
    render(<CreateCopilotSpace onDismiss={onDismiss} />)
    expect(screen.getByText('Create a new Space')).toBeInTheDocument()
  })

  it('calls onDismiss when Cancel button is clicked', async () => {
    render(<CreateCopilotSpace onDismiss={onDismiss} />)
    await userEvent.click(screen.getByText('Cancel'))
    expect(onDismiss).toHaveBeenCalled()
  })

  it('calls onCreate with name and description when Create button is clicked', async () => {
    mockFetch.mockRouteOnce('/custom_copilots', {id: 123}, {ok: true})

    render(<CreateCopilotSpace onDismiss={onDismiss} createSpace={onCreate} />)
    await userEvent.type(screen.getByLabelText('Space name'), 'Test Space')
    await userEvent.type(screen.getByLabelText('Description'), 'Test Description')
    await userEvent.click(screen.getByText('Create'))
    expect(onCreate).toHaveBeenCalled()
  })
})
