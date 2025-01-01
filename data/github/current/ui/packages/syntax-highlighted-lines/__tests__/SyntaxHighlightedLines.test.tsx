import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {SyntaxHighlightedLine} from '../SyntaxHighlightedLine'
import type {StylingDirectivesLine} from '../types'
import {useHighlight} from '../hooks/use-highlight'

jest.mock('../hooks/use-highlight')

describe('SyntaxHighlightedLine', () => {
  const mockUseHighlight = useHighlight as jest.Mock

  beforeEach(() => {
    mockUseHighlight.mockClear()
  })

  test('renders the html content without styleDirectives', () => {
    const htmlContent = 'Hello World'
    render(<SyntaxHighlightedLine html={htmlContent} styleDirectives={undefined} />)
    expect(screen.getByText('Hello World')).toBeInTheDocument()
    expect(mockUseHighlight).toHaveBeenCalledWith(expect.any(Object), undefined)
  })

  test('renders the html content with styleDirectives', () => {
    const htmlContent = 'Hello Styled World'
    const styleDirectives: StylingDirectivesLine = [
      {s: 0, e: 5, c: 'keyword'},
      {s: 6, e: 12, c: 'string'},
    ]

    render(<SyntaxHighlightedLine html={htmlContent} styleDirectives={styleDirectives} />)
    expect(screen.getByText('Hello Styled World')).toBeInTheDocument()
    expect(mockUseHighlight).toHaveBeenCalledWith(expect.any(Object), styleDirectives)
  })

  test('handles undefined styleDirectives gracefully', () => {
    const htmlContent = 'Undefined Styles'
    render(<SyntaxHighlightedLine html={htmlContent} styleDirectives={undefined} />)
    expect(screen.getByText('Undefined Styles')).toBeInTheDocument()
    expect(mockUseHighlight).toHaveBeenCalledWith(expect.any(Object), undefined)
  })
})
