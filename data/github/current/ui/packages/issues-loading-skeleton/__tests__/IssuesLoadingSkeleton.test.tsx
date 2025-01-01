import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {IssuesLoadingSkeleton} from '../IssuesLoadingSkeleton'

test('Renders the IssuesLoadingSkeleton with specific height and width', () => {
  render(<IssuesLoadingSkeleton height="67%" width="100px" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    height: '67%',
    width: '100px',
  })
})

test('Renders the IssuesLoadingSkeleton with random width', () => {
  render(<IssuesLoadingSkeleton height="md" width="random" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    height: '20px',
  })

  // Since the randomiser function in the component always returns a width between `40%` and `79%`
  expect(skeleton).not.toHaveStyle({width: '100%'})
})

test('Renders the IssuesLoadingSkeleton when width and height are size map object', () => {
  render(<IssuesLoadingSkeleton height="md" width="sm" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    height: '20px',
    width: '16px',
  })
})

test('Renders the IssuesLoadingSkeleton when width and height are numeric', () => {
  render(<IssuesLoadingSkeleton height={20} width={30} />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    height: '20px',
    width: '30px',
  })
})

test('Renders the IssuesLoadingSkeleton with default rounded border radius', () => {
  render(<IssuesLoadingSkeleton height="md" width="sm" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    borderRadius: '3px',
  })
})

test('Renders the IssuesLoadingSkeleton with pill border radius', () => {
  render(<IssuesLoadingSkeleton height="lg" width="md" borderRadius="pill" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    borderRadius: '100px',
  })
})

test('Renders the IssuesLoadingSkeleton with elliptical border radius', () => {
  render(<IssuesLoadingSkeleton height="xl" width="lg" borderRadius="elliptical" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    borderRadius: '50%',
  })
})

test('Renders the IssuesLoadingSkeleton with custom string border radius', () => {
  render(<IssuesLoadingSkeleton height="md" width="sm" borderRadius="5px" />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    borderRadius: '5px',
  })
})

test('Renders the IssuesLoadingSkeleton with custom numeric border radius', () => {
  render(<IssuesLoadingSkeleton height="lg" width="md" borderRadius={10} />)

  const skeleton = screen.getByTestId('issues-loading-skeleton')
  expect(skeleton).toHaveStyle({
    borderRadius: '10px',
  })
})
