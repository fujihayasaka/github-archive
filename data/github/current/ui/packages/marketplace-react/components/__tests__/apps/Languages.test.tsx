import {screen, render} from '@testing-library/react'
import {Languages} from '../../apps/sidebar/Languages'

const mockLanguages = ['Ruby', 'Javascript']

describe('Languages', () => {
  it('renders the Languages section', () => {
    render(<Languages supportedLanguages={mockLanguages} />)
    expect(screen.getByRole('heading', {level: 2, name: 'Supported languages'})).toBeInTheDocument()
    expect(screen.getByText('2')).toBeInTheDocument()
    expect(screen.getByText('Ruby and Javascript')).toBeInTheDocument()
  })

  it('does not render if no languages', () => {
    render(<Languages supportedLanguages={[]} />)
    expect(screen.queryByTestId('languages')).not.toBeInTheDocument()
  })
})
