import {render, screen, within} from '@testing-library/react'
import {testIdProps} from '@github-ui/test-id-props'
import {RelationshipsListAllModal, TEST_ID_COUNTER} from '../relations-section/RelationshipsListAllModal'

test('RelationshipsListAllModal renders a dialog containing the passed title with proper counter', async () => {
  const testProps = {
    dialogTitle: 'Dialog Title',
    countOpenItems: 10,
    onClose: () => null,
  }
  render(<RelationshipsListAllModal {...testProps} />)

  const dialog = await screen.findByRole('dialog')
  expect(dialog).toBeInTheDocument()

  const dialogTitle = within(dialog).queryByText(testProps.dialogTitle)
  expect(dialogTitle).toBeInTheDocument()

  const counterElement = screen.getByTestId(TEST_ID_COUNTER)
  expect(counterElement).toBeInTheDocument()
  expect(counterElement).toHaveTextContent(testProps.countOpenItems.toString())
})

test('RelationshipsListAllModal renders children content as dialog children', async () => {
  const testProps = {
    dialogTitle: 'title',
    countOpenItems: 0,
    onClose: () => null,
  }
  const testId = '__test-children-content'
  const childContent = <div {...testIdProps(testId)}>Some text content</div>

  render(<RelationshipsListAllModal {...testProps}>{childContent}</RelationshipsListAllModal>)

  expect(await screen.findByRole('dialog')).toBeInTheDocument()

  const childElement = screen.getByTestId(testId)
  expect(childElement).toBeInTheDocument()
})
