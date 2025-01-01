import {render as reactRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ExpandableContent, type ExpandableContentProps} from '../ExpandableContent'
import {describe, expect, it} from '@github-ui/tests'

const defaultProps: ExpandableContentProps = {
  collapsedContent: <div data-testid="collapsed-content">A little bit of content</div>,
  expandedContent: <div data-testid="expanded-content">A lot lot lot lot lot lot lot lot lot lot more content</div>,
}

const render = (props: Partial<ExpandableContentProps> = {}) =>
  reactRender(<ExpandableContent {...defaultProps} {...props} />)

describe('ExpandableContent', () => {
  it('initially renders the collapsed content', () => {
    render()

    expect(screen.getByTestId('collapsed-content')).toBeInTheDocument()
    expect(screen.queryByTestId('expanded-content')).not.toBeInTheDocument()
    expect(screen.getByText('Show more')).toBeInTheDocument()
  })

  it('shows the expanded content when "Show more" is clicked', async () => {
    const {user} = render()

    await user.click(screen.getByText('Show more'))

    expect(screen.queryByTestId('collapsed-content')).not.toBeInTheDocument()
    expect(screen.getByTestId('expanded-content')).toBeInTheDocument()
    expect(screen.getByText('Show less')).toBeInTheDocument()
  })

  it('returns to less content when "Show less" is clicked', async () => {
    const {user} = render()

    await user.click(screen.getByText('Show more'))
    await user.click(screen.getByText('Show less'))

    expect(screen.getByTestId('collapsed-content')).toBeInTheDocument()
    expect(screen.queryByTestId('expanded-content')).not.toBeInTheDocument()
    expect(screen.getByText('Show more')).toBeInTheDocument()
  })
})
