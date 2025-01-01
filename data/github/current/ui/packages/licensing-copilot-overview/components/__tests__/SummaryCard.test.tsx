import {render, screen} from '@testing-library/react'
import {SummaryCard} from '../SummaryCard'
import {ShieldCheckIcon} from '@primer/octicons-react'

const defaultTestProps = {
  headerIconComponent: ShieldCheckIcon,
  title: 'Default Title',
  children: <div>Default Card Body</div>,
}
const renderSummaryCard = (overrideProps = {}) => {
  const combinedProps = {...defaultTestProps, ...overrideProps}
  return render(<SummaryCard {...combinedProps} />)
}

describe('SummaryCard Component', () => {
  test('happy path: check that title is rendered', () => {
    renderSummaryCard({title: 'Copilot'})

    const titleEl = screen.queryByTestId('summary-card-title')
    expect(titleEl).toBeInTheDocument()
    expect(titleEl).toHaveTextContent('Copilot')
  })

  test('when card body is not provided, should not be rendered', () => {
    renderSummaryCard({children: undefined})

    const bodyContainerEl = screen.queryByTestId('summary-card-body')
    expect(bodyContainerEl).not.toBeInTheDocument()
  })

  test('when card body is not provided, class .summaryCardHeaderNoBody should be included on the header', () => {
    renderSummaryCard({children: undefined})

    const header = screen.queryByTestId('summary-card-header')
    expect(header).toHaveClass('summaryCardHeaderNoBody')
  })

  test('when card body is provided, should be rendered', () => {
    renderSummaryCard({cardBody: <div>Card Body</div>})

    const bodyContainerEl = screen.queryByTestId('summary-card-body')
    expect(bodyContainerEl).toBeInTheDocument()
    expect(bodyContainerEl).toHaveTextContent('Card Body')
  })

  test('when card body is provided, class .summaryCardHeaderNoBody should not be included on the header', () => {
    renderSummaryCard({cardBody: <div>Something</div>})

    const header = screen.queryByTestId('summary-card-header')
    expect(header).not.toHaveClass('summaryCardHeaderNoBody')
  })

  test('when header buttons are provided, should be rendered', () => {
    renderSummaryCard({headerButtons: <div>Header Buttons</div>})

    const headerButtons = screen.queryByTestId('summary-card-header-buttons')
    expect(headerButtons).toBeInTheDocument()
    expect(headerButtons).toHaveTextContent('Header Buttons')
  })

  test('when header buttons are not provided, should not be rendered', () => {
    renderSummaryCard({headerButtons: undefined})
    const headerButtons = screen.queryByTestId('summary-card-header-buttons')
    expect(headerButtons).not.toBeInTheDocument()
  })
})
