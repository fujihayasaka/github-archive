import {render, screen} from '@testing-library/react'
import ProgressBar from '../ProgressBar'

test('renders a single progress bar', () => {
  render(<ProgressBar data={[{progress: 30}]} />)

  expect(screen.getAllByRole('progressbar')).toBeTruthy()
  expect(screen.getByRole('progressbar', {value: {now: 30}})).toHaveAttribute('aria-valuenow', '30')
})

test('renders a multi-progress bar', () => {
  const data = [
    {progress: 20, label: 'Item'},
    {progress: 30, label: 'Item'},
  ]
  render(<ProgressBar data={data} />)

  expect(screen.getAllByRole('progressbar')).toBeTruthy()
  expect(screen.getAllByLabelText('Item')).toHaveLength(2)
})
