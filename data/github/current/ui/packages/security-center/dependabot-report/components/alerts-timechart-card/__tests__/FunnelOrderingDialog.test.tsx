import {setupUserEvent} from '@github-ui/react-core/test-utils'
import {render, screen} from '@testing-library/react'

import {FunnelOrderingDialog} from '../FunnelOrderingDialog'

describe('FunnelOrderingDialog', () => {
  const mockInitialOrder = ['has:patch', 'severity:critical,high', 'epss_percentage:>=0.01']

  it('should render all items in initial order', () => {
    render(<FunnelOrderingDialog initialOrder={mockInitialOrder} onSubmit={jest.fn()} closeDialog={jest.fn()} />)

    for (const item of mockInitialOrder) {
      expect(screen.getByText(item)).toBeInTheDocument()
    }

    expect(screen.getByText('Configure funnel order')).toBeInTheDocument()
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  it('should call onSubmit with correct reordered values when Move is clicked', async () => {
    const user = setupUserEvent()
    const mockSubmit = jest.fn()
    const mockClose = jest.fn()

    render(<FunnelOrderingDialog initialOrder={mockInitialOrder} onSubmit={mockSubmit} closeDialog={mockClose} />)

    const moveButton = screen.getByRole('button', {name: 'Move'})
    await user.click(moveButton)

    // Should match original order since no drag occurred
    expect(mockSubmit).toHaveBeenCalledWith(mockInitialOrder)
    expect(mockClose).toHaveBeenCalled()
  })

  it('should call closeDialog when the close icon is clicked', async () => {
    const user = setupUserEvent()
    const mockClose = jest.fn()

    render(<FunnelOrderingDialog initialOrder={mockInitialOrder} onSubmit={jest.fn()} closeDialog={mockClose} />)

    const closeIcon = screen.getByRole('button', {name: 'Close'})
    await user.click(closeIcon)

    expect(mockClose).toHaveBeenCalled()
  })
})
