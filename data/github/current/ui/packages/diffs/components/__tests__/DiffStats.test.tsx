import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {calculateDiffSquareCounts, DiffStats} from '../DiffStats'

describe('DiffStats', () => {
  test('renders the correct diff squares', () => {
    render(<DiffStats linesAdded={42} linesDeleted={50} linesChanged={99} />)

    expect(screen.queryAllByTestId('addition diffstat')).toHaveLength(2)
    expect(screen.queryAllByTestId('deletion diffstat')).toHaveLength(2)
    expect(screen.queryAllByTestId('neutral diffstat')).toHaveLength(1)
  })

  test('does not render if stats are not supplied', () => {
    render(<DiffStats linesAdded={undefined} linesDeleted={undefined} linesChanged={undefined} />)

    expect(screen.queryAllByTestId('addition diffstat')).toHaveLength(0)
    expect(screen.queryAllByTestId('deletion diffstat')).toHaveLength(0)
    expect(screen.queryAllByTestId('neutral diffstat')).toHaveLength(0)
  })

  test('it renders the correct squares when there are no lines added', () => {
    render(<DiffStats linesAdded={0} linesDeleted={50} linesChanged={50} />)

    expect(screen.queryAllByTestId('addition diffstat')).toHaveLength(0)
    expect(screen.queryAllByTestId('deletion diffstat')).toHaveLength(5)
    expect(screen.queryAllByTestId('neutral diffstat')).toHaveLength(0)
  })

  test('it renders the correct squares when there are no lines deleted', () => {
    render(<DiffStats linesAdded={50} linesDeleted={0} linesChanged={50} />)

    expect(screen.queryAllByTestId('addition diffstat')).toHaveLength(5)
    expect(screen.queryAllByTestId('deletion diffstat')).toHaveLength(0)
    expect(screen.queryAllByTestId('neutral diffstat')).toHaveLength(0)
  })

  test('it doesnt render if there are no lines changed', () => {
    render(<DiffStats linesAdded={10} linesDeleted={10} linesChanged={0} />)

    expect(screen.queryAllByTestId('addition diffstat')).toHaveLength(0)
    expect(screen.queryAllByTestId('deletion diffstat')).toHaveLength(0)
    expect(screen.queryAllByTestId('neutral diffstat')).toHaveLength(0)
  })
})

describe('calculateDiffSquareCounts', () => {
  describe('when linesChanged is greater than totalSquares', () => {
    test('returns correct square counts with a mix of additions and deletions', () => {
      const result = calculateDiffSquareCounts(42, 50, 99)
      expect(result.greenSquares).toBe(2)
      expect(result.redSquares).toBe(2)
      expect(result.graySquares).toBe(1)
    })

    test('calculateDiffSquareCounts returns correct square counts when no lines are added', () => {
      const result = calculateDiffSquareCounts(0, 10, 10)
      expect(result.greenSquares).toBe(0)
      expect(result.redSquares).toBe(5)
      expect(result.graySquares).toBe(0)
    })

    test('calculateDiffSquareCounts returns correct square counts when no lines are deleted', () => {
      const result = calculateDiffSquareCounts(10, 0, 10)
      expect(result.greenSquares).toBe(5)
      expect(result.redSquares).toBe(0)
      expect(result.graySquares).toBe(0)
    })
  })

  describe('when linesChanged is less than totalSquares', () => {
    test('calculateDiffSquareCounts returns correct square counts when no lines are added or deleted', () => {
      const result = calculateDiffSquareCounts(0, 0, 0)
      expect(result.greenSquares).toBe(0)
      expect(result.redSquares).toBe(0)
      expect(result.graySquares).toBe(5)
    })

    test('calculateDiffSquareCounts returns correct square counts when no lines are added', () => {
      const result = calculateDiffSquareCounts(0, 1, 1)
      expect(result.greenSquares).toBe(0)
      expect(result.redSquares).toBe(1)
      expect(result.graySquares).toBe(4)
    })

    test('calculateDiffSquareCounts returns correct square counts when no lines are deleted', () => {
      const result = calculateDiffSquareCounts(1, 0, 1)
      expect(result.greenSquares).toBe(1)
      expect(result.redSquares).toBe(0)
      expect(result.graySquares).toBe(4)
    })
  })
})
