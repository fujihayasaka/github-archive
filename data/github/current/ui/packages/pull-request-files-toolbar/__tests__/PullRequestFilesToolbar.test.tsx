import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PullRequestFilesToolbarPartial} from '../PullRequestFilesToolbar'
import {getPullRequestFilesToolbarMockData} from '../test-utils/mock-data'

test('Renders the PullRequestFilesToolbar', () => {
  render(<PullRequestFilesToolbarPartial toolbarPayload={getPullRequestFilesToolbarMockData()} />)

  // Expand Button
  expect(screen.getByTestId('expand-pr-toolbar-expand-button')).toBeInTheDocument()

  // Viewed File Progress
  expect(screen.getByText('viewed')).toBeInTheDocument()
  // We need to use element type and textContent mapper here as the "# / # viewed" is wrapped in a parent <SPAN> element and broken up by multiple children <span> elements.
  expect(
    screen.getByText((_, element) => element?.nodeName === 'SPAN' && element.textContent === '1 / 2 viewed'),
  ).toBeInTheDocument()

  // Open Comments Side Panel Button
  expect(screen.getByLabelText('Open comments side panel')).toBeInTheDocument()

  // Open Annotations Side Panel Button
  expect(screen.getByLabelText('Open annotations side panel')).toBeInTheDocument()

  // Review Menu
  expect(screen.getByText('Submit review')).toBeInTheDocument()
})
