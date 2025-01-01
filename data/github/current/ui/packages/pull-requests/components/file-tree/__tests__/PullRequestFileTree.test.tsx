import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PullRequestFileTree, type PullRequestFileTreeProps} from '../PullRequestFileTree'
import {getMockFileTreePageData} from '../../../test-utils/files-changed/file-tree-mock-data'
import {
  defaultMockFileFilterProps,
  TestFileFilterComponent,
} from '../../../test-utils/files-changed/file-filter-mock-data'
import {mockUseCommentCountFromMarkersData} from '../../../test-utils/files-changed/markers-mock-data'
import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'

jest.mock('../../../page-data/loaders/use-markers-data')

function TestComponent({commentsCount, ...props}: Partial<PullRequestFileTreeProps> & {commentsCount?: number}) {
  const mockData = getMockFileTreePageData()

  mockUseCommentCountFromMarkersData({
    isSuccess: true,
    data: commentsCount ?? 0,
  })

  return (
    <PageDataContextProvider basePageDataUrl="">
      <PullRequestFileTree
        filteredDiffs={mockData.filteredDiffs}
        fileFilter={<TestFileFilterComponent {...defaultMockFileFilterProps} />}
        {...defaultMockFileFilterProps}
        {...props}
      />
    </PageDataContextProvider>
  )
}

test('Renders the PullRequestFileTree', () => {
  render(<TestComponent />)

  // verify text filter was rendered
  expect(screen.getByRole('textbox', {name: 'Filter files…'})).toBeInTheDocument()

  // verify filter menu was rendered
  expect(screen.getByRole('button', {name: 'Filter options'})).toBeInTheDocument()

  // verify file tree was rendered
  expect(screen.getByRole('heading', {name: 'File tree'})).toBeInTheDocument()
  expect(screen.getByRole('tree', {name: 'File Tree'})).toBeInTheDocument()
  expect(screen.queryByRole('treeitem', {name: 'index.js-file-tree-comment-count'})).not.toBeInTheDocument()

  expect(screen.getByRole('treeitem', {name: 'src'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'components'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'Component.css has notice annotations'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'Component.js has warning annotations'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'Component.test.js has failure annotations'})).toBeInTheDocument()
  expect(screen.getByRole('treeitem', {name: 'index.js has notice annotations'})).toBeInTheDocument()
})

test('Renders the PullRequestFileTree with comment', () => {
  render(<TestComponent commentsCount={1} />)

  expect(
    screen.getByRole('treeitem', {name: 'Component.css has 1 comment and has notice annotations'}),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('treeitem', {name: 'Component.js has 1 comment and has warning annotations'}),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('treeitem', {name: 'Component.test.js has 1 comment and has failure annotations'}),
  ).toBeInTheDocument()
})

test('Renders the PullRequestFileTree with multiple comments', () => {
  render(<TestComponent commentsCount={2} />)

  expect(
    screen.getByRole('treeitem', {name: 'Component.css has 2 comments and has notice annotations'}),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('treeitem', {name: 'Component.js has 2 comments and has warning annotations'}),
  ).toBeInTheDocument()
  expect(
    screen.getByRole('treeitem', {name: 'Component.test.js has 2 comments and has failure annotations'}),
  ).toBeInTheDocument()
})

test('onFileSelected is triggered when selecting a file', async () => {
  const onFileSelected = jest.fn()

  const {user} = render(<TestComponent onFileSelected={onFileSelected} />)

  const fileItem = screen.getByRole('treeitem', {name: 'Component.css has notice annotations'})

  await user.click(fileItem)

  expect(onFileSelected).toHaveBeenCalled()
})

test('onFileSelected is not triggered when selecting a directory', async () => {
  const onFileSelected = jest.fn()

  const {user} = render(<TestComponent onFileSelected={onFileSelected} />)

  const directoryItem = screen.getByRole('treeitem', {name: 'src'})

  await user.click(directoryItem)

  expect(onFileSelected).not.toHaveBeenCalled()
})
