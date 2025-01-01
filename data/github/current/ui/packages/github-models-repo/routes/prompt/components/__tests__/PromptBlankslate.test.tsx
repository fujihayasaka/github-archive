import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {PromptBlankslate} from '../PromptBlankslate'

describe('PromptBlankslate', () => {
  it('renders', () => {
    render(<PromptBlankslate />)
    expect(screen.getByRole('heading', {name: 'Iterate on your prompt', level: 2})).toBeInTheDocument()
    expect(screen.getByRole('paragraph')).toHaveTextContent(/Use the prompt editor to run a single prompt repeatedly/)
  })
})
