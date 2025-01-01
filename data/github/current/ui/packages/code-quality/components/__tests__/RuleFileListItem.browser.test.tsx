import {render as reactRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RuleFileListItem, type RuleFileListItemProps} from '../RuleFileListItem'
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

const defaultProps: RuleFileListItemProps = {
  file: {
    filePath: 'src/components/Example.tsx',
    findingsCount: 3,
  },
}

const render = (props: Partial<RuleFileListItemProps> = {}) =>
  reactRender(<RuleFileListItem {...defaultProps} {...props} />, {
    wrapper: Wrapper,
  })

describe('RuleFileListItem', () => {
  it('renders the file path', () => {
    render()

    expect(screen.getByText(defaultProps.file.filePath)).toBeInTheDocument()
  })

  it('does not render a counter label when there is only one finding', () => {
    const file = {
      filePath: 'src/components/Example.tsx',
      findingsCount: 1,
    }

    render({file})

    expect(screen.queryByText('1')).not.toBeInTheDocument()
  })

  it('renders a counter label when there are multiple findings', () => {
    const file = {
      filePath: 'src/components/Example.tsx',
      findingsCount: 3,
    }

    render({file})

    const counterLabel = screen.getByText('3')
    expect(counterLabel).toBeInTheDocument()
  })

  it('includes a file icon as leading visual', () => {
    render()

    expect(screen.getByText('File')).toBeInTheDocument()
  })
})
