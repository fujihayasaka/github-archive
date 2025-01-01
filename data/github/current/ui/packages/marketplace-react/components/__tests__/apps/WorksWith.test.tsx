import {render, screen} from '@testing-library/react'
import {WorksWith} from '../../apps/sidebar/WorksWith'

describe('WorksWith', () => {
  it('renders the WorksWith section', () => {
    render(<WorksWith isCopilotApp />)
    expect(screen.getByRole('heading', {name: 'Works with', level: 2})).toBeInTheDocument()
    expect(screen.getByText('Copilot Chat, Copilot in the IDE')).toBeInTheDocument()
  })

  it('does not render if not a copilot app', () => {
    render(<WorksWith isCopilotApp={false} />)
    expect(screen.queryByTestId('apps-works-with')).not.toBeInTheDocument()
  })
})
