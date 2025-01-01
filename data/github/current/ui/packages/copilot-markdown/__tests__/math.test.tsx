// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {render} from '@github-ui/react-core/test-utils'
import {MarkdownRenderer} from '../MarkdownRenderer'
import {screen} from '@testing-library/react'

describe('math extension', () => {
  it('renders ChatGPT style block math', () => {
    render(<MarkdownRenderer markdown={'a\n\n[ b ]\n\nc'} />)
    expect(screen.getByText('b')).toHaveClass('js-display-math')
  })

  it('renders ChatGPT style block math wrapped in newlines', () => {
    render(<MarkdownRenderer markdown={'a\n\n[\nb\n]\n\nc'} />)
    expect(screen.getByText('b')).toHaveClass('js-display-math')
  })

  it('renders ChatGPT style inline math', () => {
    render(<MarkdownRenderer markdown={'a ( b ) c'} />)
    expect(screen.getByText('b')).toHaveClass('js-inline-math')
  })
})
