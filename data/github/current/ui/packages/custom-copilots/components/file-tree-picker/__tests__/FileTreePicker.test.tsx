import type {DirectoryItem} from '@github-ui/code-view-types'
import {render, setupUserEvent, type User} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {FileTreeControlProvider} from '@github-ui/repos-file-tree-view'
import {FilesPageInfoProvider, type FilesPageInfo} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {FileQueryContext} from '@github-ui/code-view-shared/contexts/FileQueryContext'
import {CurrentRepositoryProvider, type Repository} from '@github-ui/current-repository'
import type {RefInfo} from '@github-ui/repos-types'
import {FileTreePicker} from '../FileTreePicker'

jest.mock('@github-ui/code-view-shared/hooks/use-repos-analytics', () => {
  return {
    __esModule: true,
    useReposAnalytics: () => ({sendRepoClickEvent: jest.fn()}),
  }
})

// eslint-disable-next-line compat/compat
window.requestIdleCallback = jest.fn()
window.open = jest.fn()
jest.useFakeTimers()

// Helper function to create test wrapper
function Wrap({children}: React.PropsWithChildren) {
  const repo = {name: 'repo', ownerLogin: 'owner'} as Repository
  const refInfo = {name: 'main', currentOid: '2dead2be'} as RefInfo
  const infoProps = {refInfo, path: '/', action: 'tree'} as FilesPageInfo
  const noop = () => {}
  return (
    <CurrentRepositoryProvider repository={repo}>
      <FileQueryContext.Provider value={{query: '', setQuery: noop}}>
        <FileTreeControlProvider>
          <FilesPageInfoProvider {...infoProps}>{children}</FilesPageInfoProvider>
        </FileTreeControlProvider>
      </FileQueryContext.Provider>
    </CurrentRepositoryProvider>
  )
}

async function toggleExpanded(name: string | RegExp, user: User) {
  // eslint-disable-next-line testing-library/no-node-access
  const parentExpandButton = screen.getByRole('treeitem', {name}).querySelector('.PRIVATE_TreeView-item-toggle')!
  await user.click(parentExpandButton)
}

describe('FileTreePicker', () => {
  const files = {
    doc: {
      name: 'doc.md',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'docs/doc.md',
    } as DirectoryItem,
    readme: {
      name: 'README.md',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'README.md',
    } as DirectoryItem,
  }

  const dirs = {
    docs: {
      name: 'docs',
      contentType: 'directory',
      hasSimplifiedPath: false,
      path: 'docs',
      totalCount: 1,
    } as DirectoryItem,
  }

  const treeRootItems = [
    {items: [{items: [], data: files.doc}], data: dirs.docs},
    {items: [], data: files.readme},
  ]

  const baseProps = {
    rootItems: treeRootItems,
    setRootItems: () => undefined,
    loading: false,
    fetchError: false,
    processingTime: 10,
    directoryNavigateOnClick: false,
    navigateOnClick: false,
    getItemUrl: () => 'any-url',
  }

  const nestedDirs = {
    parentDir: {
      name: 'parent',
      contentType: 'directory',
      hasSimplifiedPath: false,
      path: 'parent',
      totalCount: 2,
    } as DirectoryItem,
    parentDirFile: {
      name: 'file.txt',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'parent/file.txt',
    } as DirectoryItem,
    childDir: {
      name: 'child',
      contentType: 'directory',
      hasSimplifiedPath: false,
      path: 'parent/child',
      totalCount: 1,
    } as DirectoryItem,
    childFile: {
      name: 'file.txt',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'parent/child/file.txt',
    } as DirectoryItem,
  }

  const nestedRootItems = [
    {
      data: nestedDirs.parentDir,
      items: [
        {
          data: nestedDirs.childDir,
          items: [{items: [], data: nestedDirs.childFile}],
        },
        {
          data: nestedDirs.parentDirFile,
          items: [],
        },
      ],
    },
  ]

  it('renders tree with selection UI', () => {
    render(
      <Wrap>
        <FileTreePicker expandedPath="" {...baseProps} />
      </Wrap>,
    )
    expect(screen.getByTestId('README.md-file-item')).toBeVisible()
    expect(screen.getByTestId('docs-directory-item')).toBeVisible()
  })

  it('handles single file selection', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()
    render(
      <Wrap>
        <FileTreePicker {...baseProps} expandedPath="" onSelectionChange={onSelectionChange} />
      </Wrap>,
    )

    const readmeItem = screen.getByTestId('README.md-file-item')
    await user.click(readmeItem)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set(['README.md']))
  })

  it('handles directory selection including all children', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()
    render(
      <Wrap>
        <FileTreePicker expandedPath="" {...baseProps} onSelectionChange={onSelectionChange} />
      </Wrap>,
    )

    const docsDir = screen.getByTestId('docs-directory-item')
    await user.click(docsDir)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set(['docs', 'docs/doc.md']))
  })

  it('handles directory deselection', async () => {
    const user = setupUserEvent()
    const initialSelection = new Set(['docs', 'docs/doc.md'])
    const onSelectionChange = jest.fn()

    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          expandedPath=""
          selectedItems={initialSelection}
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    const docsDir = screen.getByTestId('docs-directory-item')
    await user.click(docsDir)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set())
  })

  it('handles nested directory selection', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()
    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath=""
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    // First we need to expand the parent directory
    await toggleExpanded(/parent/, user)

    // Now we can click the child directory
    const childDir = screen.getByTestId('parent/child-directory-item')
    await user.click(childDir)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set(['parent/child', 'parent/child/file.txt']))
  })

  it('handles nested directory deselection', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()
    const initialSelection = new Set(['parent/child', 'parent/child/file.txt'])

    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath=""
          selectedItems={initialSelection}
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    await toggleExpanded(/parent/, user)

    const parentDir = screen.getByTestId('parent/child-directory-item')
    await user.click(parentDir)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set())
  })

  it('handles selecting nested directory without selecting parent', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()

    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath="parent"
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    const childDir = screen.getByTestId('parent/child-directory-item')
    await user.click(childDir)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set(['parent/child', 'parent/child/file.txt']))
  })

  it('selecting a parent should select itself and all children', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()

    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath="parent"
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    // First select the child directory
    const childDir = screen.getByTestId('parent/child-directory-item')
    await user.click(childDir)
    expect(onSelectionChange).toHaveBeenCalledWith(new Set(['parent/child', 'parent/child/file.txt']))

    onSelectionChange.mockClear()
    // Then select the parent directory
    const parentDir = screen.getByTestId('parent-directory-item')
    await user.click(parentDir)
    expect(onSelectionChange).toHaveBeenCalledWith(
      new Set(['parent', 'parent/child', 'parent/child/file.txt', 'parent/file.txt']),
    )
  })

  it('handles deselecting child directory while keeping parent selected', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()
    const initialSelection = new Set(['parent', 'parent/child', 'parent/child/file.txt'])

    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath="parent"
          selectedItems={initialSelection}
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    const childDir = screen.getByTestId('parent/child-directory-item')
    await user.click(childDir)

    expect(onSelectionChange).toHaveBeenCalledWith(new Set(['parent']))
  })

  it('handles selecting multiple directories at different levels', async () => {
    const user = setupUserEvent()
    const onSelectionChange = jest.fn()
    const moreNestedDirs = {
      parentDir: {
        name: 'parent',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'parent',
        totalCount: 3,
      } as DirectoryItem,
      siblingDir: {
        name: 'sibling',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'parent/sibling',
        totalCount: 1,
      } as DirectoryItem,
      siblingFile: {
        name: 'sibling.txt',
        contentType: 'file',
        hasSimplifiedPath: false,
        path: 'parent/sibling/sibling.txt',
      } as DirectoryItem,
      childDir: {
        name: 'child',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'parent/child',
        totalCount: 1,
      } as DirectoryItem,
      childFile: {
        name: 'file.txt',
        contentType: 'file',
        hasSimplifiedPath: false,
        path: 'parent/child/file.txt',
      } as DirectoryItem,
    }

    const moreNestedRootItems = [
      {
        items: [
          {
            items: [{items: [], data: moreNestedDirs.childFile}],
            data: moreNestedDirs.childDir,
          },
          {
            items: [{items: [], data: moreNestedDirs.siblingFile}],
            data: moreNestedDirs.siblingDir,
          },
        ],
        data: moreNestedDirs.parentDir,
      },
    ]

    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          selectedItems={new Set(['parent/child', 'parent/child/file.txt'])}
          rootItems={moreNestedRootItems}
          expandedPath="parent"
          onSelectionChange={onSelectionChange}
        />
      </Wrap>,
    )

    // Select the sibling directory
    const siblingDir = screen.getByTestId('parent/sibling-directory-item')
    await user.click(siblingDir)
    expect(onSelectionChange).toHaveBeenCalledWith(
      new Set(['parent/child', 'parent/child/file.txt', 'parent/sibling', 'parent/sibling/sibling.txt']),
    )
  })

  it('expands to show active item when expandedPath is set', () => {
    render(
      <Wrap>
        <FileTreePicker {...baseProps} expandedPath="parent/child/file.txt" rootItems={nestedRootItems} />
      </Wrap>,
    )

    // Verify tree structure is rendered correctly with auto-expansion
    expect(screen.getByTestId('parent-directory-item')).toBeInTheDocument()
    expect(screen.getByTestId('parent/child-directory-item')).toBeInTheDocument()
    expect(screen.getByTestId('parent/child/file.txt-file-item')).toBeInTheDocument()
  })

  it('expands to show active directory when expandedPath is set to a directory', () => {
    render(
      <Wrap>
        <FileTreePicker {...baseProps} expandedPath="parent/child" rootItems={nestedRootItems} />
      </Wrap>,
    )

    // Verify tree structure is rendered correctly with auto-expansion
    expect(screen.getByTestId('parent-directory-item')).toBeInTheDocument()
    expect(screen.getByTestId('parent/child-directory-item')).toBeInTheDocument()
  })

  it('renders checkboxes in unchecked state by default', () => {
    render(
      <Wrap>
        <FileTreePicker expandedPath="" {...baseProps} />
      </Wrap>,
    )

    const checkbox = screen.getByRole('checkbox', {name: 'Select README.md'})
    expect(checkbox).toBeInTheDocument()
    expect(checkbox).not.toBeChecked()
  })

  it('renders checkbox checked when item is selected', () => {
    render(
      <Wrap>
        <FileTreePicker {...baseProps} expandedPath="" selectedItems={new Set(['README.md'])} />
      </Wrap>,
    )

    const checkbox = screen.getByRole('checkbox', {name: 'Select README.md'})
    expect(checkbox).toBeChecked()
  })

  it('shows indeterminate checkbox state when directory is partially selected', async () => {
    const user = setupUserEvent()
    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath="parent"
          selectedItems={new Set(['parent/child'])}
        />
      </Wrap>,
    )

    await toggleExpanded(/parent/, user)

    const parentCheckbox = screen.getByRole('checkbox', {name: 'Select parent'})
    expect(parentCheckbox).toHaveAttribute('data-indeterminate', 'true')
    expect(parentCheckbox).not.toBeChecked()
  })

  it('shows checked state when directory and all children are selected', () => {
    render(
      <Wrap>
        <FileTreePicker
          {...baseProps}
          rootItems={nestedRootItems}
          expandedPath="parent"
          selectedItems={new Set(['parent', 'parent/child', 'parent/child/file.txt', 'parent/file.txt'])}
        />
      </Wrap>,
    )

    const parentCheckbox = screen.getByRole('checkbox', {name: 'Select parent'})
    expect(parentCheckbox).toBeChecked()
    expect(parentCheckbox).not.toHaveAttribute('data-indeterminate')
  })

  // Cleanup after all tests
  afterEach(() => {
    jest.useRealTimers()
    jest.restoreAllMocks()
  })
})
