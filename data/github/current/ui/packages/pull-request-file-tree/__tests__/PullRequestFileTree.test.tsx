import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PullRequestFileTree} from '../PullRequestFileTree'
import {getMockPullRequestFileTreePageData} from '../test-utils/mock-data'
import type {DiffDelta} from '@github-ui/diff-file-tree/diff-file-tree-helpers'

const setFilterState = jest.fn()

test('Renders the PullRequestFileTree', () => {
  const mockData = getMockPullRequestFileTreePageData()

  render(
    <PullRequestFileTree
      baseRefOid={mockData.baseRefOid}
      commits={mockData.commits}
      diffs={mockData.diffs}
      ownerLogin={mockData.ownerLogin}
      pathName={mockData.pathName}
      pullRequestNumber={mockData.pullRequestNumber}
      pullRequestId={mockData.pullRequestId}
      repositoryName={mockData.repositoryName}
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
      setFileFilterState={setFilterState}
      filteredDiffs={mockData.diffs as DiffDelta[]}
    />,
  )

  // verify commits selector was rendered
  expect(screen.getByRole('button', {name: 'All changes'})).toBeInTheDocument()

  // verify text filter was rendered
  expect(screen.getByRole('textbox', {name: 'Filter files…'})).toBeInTheDocument()

  // verify filter menu was rendered
  expect(screen.getByRole('button', {name: 'Filter'})).toBeInTheDocument()

  // verify file tree was rendered
  expect(screen.getByRole('heading', {name: 'File tree'})).toBeInTheDocument()
  expect(screen.getByRole('tree', {name: 'File Tree'})).toBeInTheDocument()
  expect(screen.queryByRole('treeitem', {name: 'index.js-file-tree-comment-count'})).not.toBeInTheDocument()

  expect(screen.getByRole('treeitem', {name: 'src'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'components'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'Component.css has notice annotations'})).toBeInTheDocument()
  expect(
    screen.getByRole('treeitem', {name: 'Component.js has 1 comment and has warning annotations'}),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('treeitem', {name: 'Component.test.js has 2 comments and has failure annotations'}),
  ).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'index.js has notice annotations'})).toBeInTheDocument()
})

test('onFileSelected is triggered when selecting a file', async () => {
  const mockData = getMockPullRequestFileTreePageData()
  const onFileSelected = jest.fn()

  const {user} = render(
    <PullRequestFileTree
      baseRefOid={mockData.baseRefOid}
      commits={mockData.commits}
      diffs={mockData.diffs}
      ownerLogin={mockData.ownerLogin}
      pathName={mockData.pathName}
      pullRequestNumber={mockData.pullRequestNumber}
      pullRequestId={mockData.pullRequestId}
      repositoryName={mockData.repositoryName}
      onFileSelected={onFileSelected}
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
      setFileFilterState={setFilterState}
      filteredDiffs={mockData.diffs as DiffDelta[]}
    />,
  )

  const fileItem = screen.getByRole('treeitem', {name: 'Component.css has notice annotations'})

  await user.click(fileItem)

  expect(onFileSelected).toHaveBeenCalled()
})

test('onFileSelected is not triggered when selecting a directory', async () => {
  const mockData = getMockPullRequestFileTreePageData()
  const onFileSelected = jest.fn()

  const {user} = render(
    <PullRequestFileTree
      baseRefOid={mockData.baseRefOid}
      commits={mockData.commits}
      diffs={mockData.diffs}
      ownerLogin={mockData.ownerLogin}
      pathName={mockData.pathName}
      pullRequestNumber={mockData.pullRequestNumber}
      pullRequestId={mockData.pullRequestId}
      repositoryName={mockData.repositoryName}
      onFileSelected={onFileSelected}
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
      setFileFilterState={setFilterState}
      filteredDiffs={mockData.diffs as DiffDelta[]}
    />,
  )

  const directoryItem = screen.getByRole('treeitem', {name: 'src'})

  await user.click(directoryItem)

  expect(onFileSelected).not.toHaveBeenCalled()
})
