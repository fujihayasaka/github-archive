import {fireEvent, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RequestForm} from '../index'
import {Link} from '@primer/react'

const instructions = {
  title: 'test title',
  Description: () => {
    return (
      <span>
        Submit a request to bypass these push protections. If granted, you may attempt this push again.{' '}
        <Link href="https://docs.github.com/secret-scanning-help" inline>
          Learn more
        </Link>
      </span>
    )
  },
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
