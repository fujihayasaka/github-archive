import {render, screen} from '@testing-library/react'
import {SummaryCard} from '../SummaryCard'
import {ProductActivationState} from '../../types/product-activation-state'
import {CheckIcon} from '@primer/octicons-react'

const defaultTestProps = {
  productActivationState: ProductActivationState.Active,
  headerIconComponent: CheckIcon,
  title: 'Default Title',
  headerMenu: <div>Default Header Menu</div>,
  children: <div>Default Card Body</div>,
}
const renderSummaryCard = (overrideProps = {}) => {
  const combinedProps = {...defaultTestProps, ...overrideProps}
  return render(<SummaryCard {...combinedProps} />)
}

describe('SummaryCard Component', () => {
  test('happy path: check that title is rendered', () => {
    renderSummaryCard({title: 'Test Title'})

    const titleEl = screen.queryByTestId('summary-card-title')
    expect(titleEl).toBeInTheDocument()
    expect(titleEl).toHaveTextContent('Test Title')
  })

  test('renders without productActivationState', () => {
    renderSummaryCard({productActivationState: null, title: 'Test Title'})

    const titleEl = screen.queryByTestId('summary-card-title')
    expect(titleEl).toBeInTheDocument()
    expect(titleEl).toHaveTextContent('Test Title')
  })

  test('when productActivationState is inactive, header should include inactive label', () => {
    renderSummaryCard({productActivationState: ProductActivationState.Inactive})

    const inactiveLabelEl = screen.queryByTestId('summary-card-label-inactive')
    expect(inactiveLabelEl).toBeInTheDocument()
  })

  test('when productActivationState is trial, header should include active trial label', () => {
    renderSummaryCard({productActivationState: ProductActivationState.Trial})

    const activeTrialLabel = screen.queryByTestId('summary-card-label-trial')
    expect(activeTrialLabel).toBeInTheDocument()
  })

  test('when productActivationState is expired trial, header should include expired trial label', () => {
    renderSummaryCard({productActivationState: ProductActivationState.TrialExpired})

    const expiredTrialLabel = screen.queryByTestId('summary-card-label-trial-expired')
    expect(expiredTrialLabel).toBeInTheDocument()
  })

  test('when header menu is provided, should be rendered', () => {
    renderSummaryCard({headerMenu: <div>Menu Item</div>})

    const headerMenuContainerEl = screen.queryByTestId('summary-card-header-menu')
    expect(headerMenuContainerEl).toBeInTheDocument()
    expect(headerMenuContainerEl).toHaveTextContent('Menu Item')
  })

  test('when header menu is not provided, none should be rendered', () => {
    renderSummaryCard({headerMenu: undefined})

    const headerMenuContainerEl = screen.queryByTestId('summary-card-header-menu')
    expect(headerMenuContainerEl).not.toBeInTheDocument()
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
    renderSummaryCard({children: <div>Card Body</div>})

    const bodyContainerEl = screen.queryByTestId('summary-card-body')
    expect(bodyContainerEl).toBeInTheDocument()
    expect(bodyContainerEl).toHaveTextContent('Card Body')
  })

  test('when card body is provided, class .summaryCardHeaderNoBody should not be included on the header', () => {
    renderSummaryCard({children: <div>Something</div>})

    const header = screen.queryByTestId('summary-card-header')
    expect(header).not.toHaveClass('summaryCardHeaderNoBody')
  })

  test('renders headerLabels when provided in the header', () => {
    renderSummaryCard({headerLabels: [<div key={1}>Label 1</div>, <div key={2}>Label 2</div>]})

    const header = screen.queryByTestId('summary-card-header')
    expect(header).toBeInTheDocument()
    expect(header).toHaveTextContent('Label 1')
    expect(header).toHaveTextContent('Label 2')
  })
})
