import {render, screen} from '@testing-library/react'
import {MetricWithDifferenceCell} from '../../components/tables/MetricWithDifferenceCell'

describe('MetricWithDifferenceCell', () => {
  it('renders the metric and difference correctly', () => {
    render(<MetricWithDifferenceCell average={25} percentDifference={1.0} />)
    expect(screen.getByText('25')).toBeInTheDocument()
    expect(
      screen.getByText((content, element) => {
        const hasText = (node: Element | null) => node?.textContent === '+'
        return element?.tagName.toLowerCase() === 'span' && hasText(element)
      }),
    ).toBeInTheDocument()
    expect(screen.getByText(/100%/)).toBeInTheDocument()
  })
  it('renders the metric and difference with negative values correctly', () => {
    render(<MetricWithDifferenceCell average={-10} percentDifference={-0.5} />)
    expect(screen.getByText('-10')).toBeInTheDocument()
    expect(
      screen.getByText((content, element) => {
        const hasText = (node: Element | null) => node?.textContent === '-'
        return element?.tagName.toLowerCase() === 'span' && hasText(element)
      }),
    ).toBeInTheDocument()
    expect(screen.getByText(/50%/)).toBeInTheDocument()
  })
  it('renders the metric and difference with zero values correctly', () => {
    render(<MetricWithDifferenceCell average={0} percentDifference={0} />)
    expect(screen.getByText('0')).toBeInTheDocument()
    expect(
      screen.getByText((content, element) => {
        const hasText = (node: Element | null) => node?.textContent === '+'
        return element?.tagName.toLowerCase() === 'span' && hasText(element)
      }),
    ).toBeInTheDocument()
    expect(screen.getByText(/0%/)).toBeInTheDocument()
  })
  it('renders the metric with hour suffix correctly', () => {
    render(<MetricWithDifferenceCell average={25} percentDifference={1.0} hourSuffix />)
    expect(screen.getByText('25h')).toBeInTheDocument()
    expect(
      screen.getByText((content, element) => {
        const hasText = (node: Element | null) => node?.textContent === '+'
        return element?.tagName.toLowerCase() === 'span' && hasText(element)
      }),
    ).toBeInTheDocument()
    expect(screen.getByText(/100%/)).toBeInTheDocument()
  })
})
