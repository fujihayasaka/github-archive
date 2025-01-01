import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PullRequestFileTree} from '../PullRequestFileTree'
import {getMockPullRequestFileTreePageData} from '../test-utils/mock-data'

test('Renders the PullRequestFileTree', () => {
  const mockData = getMockPullRequestFileTreePageData()
  render(<PullRequestFileTree />)

  // verify commits selector was rendered
  expect(screen.getByRole('button', {name: 'All changes'})).toBeInTheDocument()

  // verify text filter was rendered
  expect(screen.getByRole('textbox', {name: 'Filter files…'})).toBeInTheDocument()

  // verify filter menu was rendered
  expect(screen.getByRole('button', {name: 'Filter'})).toBeInTheDocument()

  // verify file tree was rendered
  expect(screen.getByRole('heading', {name: 'File tree'})).toBeInTheDocument()
  expect(screen.getByRole('tree', {name: 'File Tree'})).toBeInTheDocument()

  // verify expected directories and file paths were rendered
  const directoriesAndFilePaths = mockData.diffs.flatMap(diff => diff.path.split('/'))
  const expectedFileTreeItems = new Set<string>(directoriesAndFilePaths)

  for (const expectedFileTreeItem of expectedFileTreeItems) {
    expect(screen.getByRole('treeitem', {name: expectedFileTreeItem})).toBeInTheDocument()
  }
})
