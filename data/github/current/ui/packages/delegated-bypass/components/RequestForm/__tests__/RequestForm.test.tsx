import {fireEvent, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RequestForm} from '../index'

const instructions = {
  title: 'test title',
  description: 'Submit a request to bypass these push protections. If granted, you may attempt this push again.',
  Content: () => <>test content</>,
  ApproversFooter: () => <>test approvers</>,
}

test('renders RequestForm', () => {
  render(<RequestForm instructions={instructions} />)

  const commentTextarea = screen.getByRole('textbox')
  expect(commentTextarea).toBeVisible()

  const submitButton = screen.getByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(submitButton)
  const commentIsRequired = screen.getByText('A comment is required')
  expect(commentIsRequired).toBeVisible()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.change(commentTextarea, {target: {value: 'Please allow me to bypass'}})
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(submitButton)
  expect(commentIsRequired).not.toBeVisible()
})
