import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import {PullRequestFilesToolbar} from '../PullRequestFilesToolbar'
import {getPullRequestFilesToolbarMockData} from '../test-utils/mock-data'
import type {ToolbarPayload} from '../page-data/payloads/toolbar'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

function TestComponent({toolbarPayload}: {toolbarPayload: ToolbarPayload}) {
  return (
    <AliveTestProvider>
      <PullRequestFilesToolbar
        {...toolbarPayload}
        repository={toolbarPayload.pullRequest.repository}
        fileFilterState={{
          filterText: '',
          fileExtensions: new Set<string>(),
          unselectedFileExtensions: new Set<string>(),
          showCodeowners: undefined,
          showDeletedFiles: undefined,
          showOnlyManifestFiles: undefined,
          showVendorFiles: undefined,
          showViewedFiles: undefined,
        }}
        setFileFilterState={() => {}}
        filteredDiffs={[] as DiffDelta[]}
      />
    </AliveTestProvider>
  )
}

test('Renders the PullRequestFilesToolbar', () => {
  render(<TestComponent toolbarPayload={getPullRequestFilesToolbarMockData()} />)

  // Expand Button
  expect(screen.getByRole('button', {name: 'Collapse file tree'})).toBeInTheDocument()

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

test('Renders the expand pull request file tree button when collapsed', () => {
  render(<TestComponent toolbarPayload={{...getPullRequestFilesToolbarMockData(), isFileTreeExpanded: false}} />)

  // mobile and non-mobile expand buttons
  expect(screen.queryAllByRole('button', {name: 'Expand file tree'})).toHaveLength(2)
})
