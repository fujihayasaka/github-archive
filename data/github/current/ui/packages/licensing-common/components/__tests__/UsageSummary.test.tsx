import {render, screen} from '@testing-library/react'

import {UsageSummary} from '../UsageSummary'

const defaultTestProps = {
  headingLevel: 'h3' as const,
  title: 'Consumed licenses',
}

const renderUsageSummary = (overrideProps = {}) => {
  return render(<UsageSummary {...defaultTestProps} {...overrideProps} />)
}

describe('UsageSummary Component', () => {
  test('renders the title UI', () => {
    renderUsageSummary()

    const summaryHeaderTitleEl = screen.queryByTestId('usage-summary-header-title')
    expect(summaryHeaderTitleEl).toBeInTheDocument()
    expect(summaryHeaderTitleEl).toHaveTextContent('Consumed licenses')
  })

  test('renders the hint component when provided', () => {
    renderUsageSummary({usageHint: <div data-testid="hint-text">This is a hint</div>})

    const hintEl = screen.queryByTestId('hint-text')
    expect(hintEl).toBeInTheDocument()
    expect(hintEl).toHaveTextContent('This is a hint')
  })

  test('renders child elements when provided', () => {
    renderUsageSummary({children: <div data-testid="some-text">This is children</div>})

    const childrenEl = screen.queryByTestId('some-text')
    expect(childrenEl).toBeInTheDocument()
    expect(childrenEl).toHaveTextContent('This is children')
  })
})
