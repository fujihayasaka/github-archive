import {render, screen} from '@testing-library/react'
import {Metric} from '../components/Metric'
import {Grade} from '../types/grade'
import {describe, expect, it} from '@github-ui/tests'

describe('Metric', () => {
  it('renders with Grade A correctly', () => {
    render(<Metric title="Test Metric" data={{grade: Grade.A, findingsCount: 5}} />)

    expect(screen.getByText('Test Metric')).toBeInTheDocument()
    expect(screen.getByText('Excellent')).toBeInTheDocument()
    expect(screen.getByText('5 findings')).toBeInTheDocument()

    const activeSegments = screen.queryAllByLabelText('Progress segment')
    const inactiveSegments = screen.queryAllByLabelText('Inactive segment')
    expect(activeSegments.length).toBe(4)
    expect(inactiveSegments.length).toBe(0)
  })

  it('renders with Grade B correctly', () => {
    render(<Metric title="Test Metric" data={{grade: Grade.B, findingsCount: 10}} />)

    expect(screen.getByText('Good')).toBeInTheDocument()
    expect(screen.getByText('10 findings')).toBeInTheDocument()

    const activeSegments = screen.getAllByLabelText('Progress segment')
    const inactiveSegments = screen.queryAllByLabelText('Inactive segment')
    expect(activeSegments.length).toBe(3)
    expect(inactiveSegments.length).toBe(1)
  })

  it('renders with Grade C correctly', () => {
    render(<Metric title="Test Metric" data={{grade: Grade.C, findingsCount: 15}} />)

    expect(screen.getByText('Fair')).toBeInTheDocument()
    expect(screen.getByText('15 findings')).toBeInTheDocument()

    const activeSegments = screen.queryAllByLabelText('Progress segment')
    const inactiveSegments = screen.queryAllByLabelText('Inactive segment')
    expect(activeSegments.length).toBe(2)
    expect(inactiveSegments.length).toBe(2)
  })

  it('renders with Grade D correctly', () => {
    render(<Metric title="Test Metric" data={{grade: Grade.D, findingsCount: 20}} />)

    expect(screen.getByText('Needs Improvement')).toBeInTheDocument()
    expect(screen.getByText('20 findings')).toBeInTheDocument()

    const activeSegments = screen.queryAllByLabelText('Progress segment')
    const inactiveSegments = screen.getAllByLabelText('Inactive segment')
    expect(activeSegments.length).toBe(1)
    expect(inactiveSegments.length).toBe(3)
  })

  it('renders no data correctly', () => {
    render(<Metric title="Test Metric" />)

    expect(screen.getByText('Test Metric')).toBeInTheDocument()
    expect(screen.getByText('No data')).toBeInTheDocument()
    expect(screen.getByText('0 findings')).toBeInTheDocument()

    const activeSegments = screen.queryAllByLabelText('Progress segment')
    const inactiveSegments = screen.getAllByLabelText('Inactive segment')
    expect(activeSegments.length).toBe(0)
    expect(inactiveSegments.length).toBe(4)
  })
})
