import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {ExpandButton} from '../ExpandButton'

test('Renders the collapsed ExpandButton', () => {
  render(
    <ExpandButton
      ariaLabel="Expand it!"
      ariaControls="testing"
      expanded={false}
      onToggleExpanded={jest.fn()}
      testid="expand-button-test"
      alignment="left"
    />,
  )

  expect(screen.getByLabelText('Expand it!')).toBeInTheDocument()
  expect(screen.getByTestId('expand-expand-button-test')).toBeInTheDocument()
  expect(screen.queryByTestId('collapse-expand-button-test')).not.toBeInTheDocument()
})

test('Renders the expanded ExpandButton', () => {
  render(
    <ExpandButton
      ariaLabel="Expand it!"
      ariaControls="testing"
      expanded
      onToggleExpanded={jest.fn()}
      testid="expand-button-test"
      alignment="left"
    />,
  )

  expect(screen.getByLabelText('Expand it!')).toBeInTheDocument()
  expect(screen.getByTestId('collapse-expand-button-test')).toBeInTheDocument()
  expect(screen.queryByTestId('expand-expand-button-test')).not.toBeInTheDocument()
})
