import {render as reactRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RuleFileListMoreItem, type RuleFileListMoreItemProps} from '../RuleFileListMoreItem'
import {IdProvider} from '@github-ui/list-view/ListViewIdContext'
import {VariantProvider} from '@github-ui/list-view/ListViewVariantContext'
import {TitleProvider} from '@github-ui/list-view/ListViewTitleContext'
import {describe, expect, it} from '@github-ui/tests'

const Wrapper = ({children}: {children?: React.ReactNode}) => (
  <IdProvider>
    <VariantProvider>
      <TitleProvider title="">{children}</TitleProvider>
    </VariantProvider>
  </IdProvider>
)

const defaultProps: RuleFileListMoreItemProps = {
  owner: 'octodemo',
  repo: 'repo1',
  ruleId: 'rule-1',
  remainingFindingsCount: 3,
}

const render = (props: Partial<RuleFileListMoreItemProps> = {}) =>
  reactRender(<RuleFileListMoreItem {...defaultProps} {...props} />, {
    wrapper: Wrapper,
  })

describe('RuleFileListMoreItem', () => {
  it('renders the correct text for multiple findings', () => {
    render()

    expect(screen.getByText('and 3 more findings')).toBeInTheDocument()
  })

  it('renders the correct text for a single finding', () => {
    render({remainingFindingsCount: 1})

    expect(screen.getByText('and 1 more finding')).toBeInTheDocument()
  })
})
