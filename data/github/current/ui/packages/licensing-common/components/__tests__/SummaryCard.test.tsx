import {render, screen} from '@testing-library/react'
import {SummaryCard} from '../SummaryCard'
import {ProductActivationState} from '../../types/product-activation-state'
import {CheckIcon} from '@primer/octicons-react'

const defaultTestProps = {
  productActivationState: ProductActivationState.Active,
  headerIconComponent: CheckIcon,
  title: 'Default Title',
  headerMenu: <div>Default Header Menu</div>,
  headerActions: <div>Default Header Action</div>,
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

  test('when header actions are provided, should be rendered', () => {
    renderSummaryCard({headerActions: <div>Menu Item</div>})

    const headerActionsContainerEl = screen.queryByTestId('summary-card-header-actions')
    expect(headerActionsContainerEl).toBeInTheDocument()
    expect(headerActionsContainerEl).toHaveTextContent('Menu Item')
  })

  test('when header action is not provided, none should be rendered', () => {
    renderSummaryCard({headerActions: undefined})

    const headerActionsContainerEl = screen.queryByTestId('summary-card-header-actions')
    expect(headerActionsContainerEl).not.toBeInTheDocument()
  })

  test('when header menu is provided, should be rendered', () => {
    renderSummaryCard({headerMenu: <div>Action Menu Item</div>})

    const headerMenuContainerEl = screen.queryByTestId('summary-card-header-menu')
    expect(headerMenuContainerEl).toBeInTheDocument()
    expect(headerMenuContainerEl).toHaveTextContent('Action Menu Item')
  })

  test('when header menu is not provided, none should be rendered', () => {
    renderSummaryCard({headerMenu: undefined})

    const headerMenuContainerEl = screen.queryByTestId('summary-card-header-menu')
    expect(headerMenuContainerEl).not.toBeInTheDocument()
  })

  test('when card body is not provided, class .summaryCardHeaderNoBody should be included on the header', () => {
    renderSummaryCard({children: undefined})

    const header = screen.queryByTestId('summary-card-header')
    expect(header).toHaveClass('summaryCardHeaderNoBody')
  })

  test('when card body is provided, should be rendered', () => {
    renderSummaryCard({children: <div data-testid="summary-card-children">Card Body</div>})

    const bodyContainerEl = screen.queryByTestId('summary-card-children')
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
