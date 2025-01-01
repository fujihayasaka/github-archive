import '../test-utils/mocks'

import type {DirectoryItem, ReposFileTreeData} from '@github-ui/code-view-types'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'

import {App} from '../App'
import {WorkspaceEditor} from '../routes/WorkspaceEditor'
import {getWorkspaceEditorRoutePayload} from '../test-utils/mock-data'

const terminateMock = jest.fn()

// Web workers are not supported on jsdom, so we mock the minimum we need for this test,
// which will call onmessage once per each postMessage with a fixed resultset.
window.Worker = class {
  // onmessage will be replaced by the caller to handle responses
  onmessage = (data: unknown) => data
  postMessage() {
    this.onmessage({data: {query: 'any', list: ['contra', 'transport', 'ter/rain'], startTime: 20, baseCount: 4}})
  }
  terminate = terminateMock
} as unknown as typeof Worker

jest.useFakeTimers()

// Mock useNavigate
const navigateFn = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  const actual = jest.requireActual('@github-ui/use-navigate')
  return {
    ...actual,
    useNavigate: () => navigateFn,
  }
})

jest.mock('@github-ui/react-core/use-feature-flag', () => ({
  useFeatureFlag: () => true,
}))

beforeEach(() => {
  jest.clearAllMocks()
  window.localStorage.clear()
})

test('Renders the Workspace Editor landing view', () => {
  const routePayload = getWorkspaceEditorRoutePayload({path: ''})
  render(
    <App>
      <WorkspaceEditor />
    </App>,
    {
      pathname: '/owner/repo/pull/1/edit',
      routePayload,
    },
  )
  expect(screen.getByText(routePayload.fileTree['']!.items[0]!.name)).toBeInTheDocument()
})

test('Renders the Workspace Editor file edit view', () => {
  const routePayload = getWorkspaceEditorRoutePayload({path: 'path/to/file.txt'})
  render(
    <App>
      <WorkspaceEditor />
    </App>,
    {
      pathname: '/monalisa/smile/pull/1/edit/file/path/to/file.txt',
      routePayload,
    },
  )

  expect(screen.getByText(routePayload.fileTree['']!.items[0]!.name)).toBeInTheDocument()
  expect(screen.getByText('path/to/file.txt')).toBeInTheDocument()
})

test('Renders the Workspace Editor new file view', () => {
  const routePayload = getWorkspaceEditorRoutePayload({isNewFilePage: true})
  render(
    <App>
      <WorkspaceEditor />
    </App>,
    {
      pathname: '/monalisa/smile/pull/1/edit/new',
      routePayload,
    },
  )

  expect(screen.getByText('readme')).toBeInTheDocument()
  expect(screen.getByPlaceholderText('Name your file...')).toBeInTheDocument()
  expect(screen.getByText('Save')).toBeInTheDocument()
})

describe('adding new files', () => {
  test('updates commit panel', async () => {
    const routePayload = getWorkspaceEditorRoutePayload({path: '', isNewFilePage: true})
    const {user} = render(
      <App>
        <WorkspaceEditor />
      </App>,
      {
        pathname: '/monalisa/smile/pull/1/edit/new',
        routePayload,
      },
    )

    // save a file
    await user.type(screen.getByPlaceholderText('Name your file...'), 'new-file.txt')
    await user.click(screen.getByText('Save'))
    await user.click(screen.getByRole('button', {name: 'Commit changes'}))

    // confirm that the commit changes dialog gets the updated file
    expect(screen.getByRole('heading', {name: 'Commit changes'})).toBeInTheDocument()
    expect(screen.getByText('Commit message')).toBeInTheDocument()
    expect(screen.getByRole<HTMLInputElement>('checkbox').value).toBe('new-file.txt')
  })

  test('updates file tree when adding new file', async () => {
    const routePayload = getWorkspaceEditorRoutePayload({path: '', isNewFilePage: true})
    const {user} = render(
      <App>
        <WorkspaceEditor />
      </App>,
      {
        pathname: '/monalisa/smile/pull/1/edit/new',
        routePayload,
      },
    )

    // save a file
    await user.type(screen.getByPlaceholderText('Name your file...'), 'new-file.txt')
    await user.click(screen.getByText('Save'))

    // confirm that the file tree gets the updated file
    expect(
      screen.getByText('new-file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).toBeInTheDocument()
  })

  test('updates file tree when adding new directories', async () => {
    const routePayload = getWorkspaceEditorRoutePayload({path: '', isNewFilePage: true})
    const {user} = render(
      <App>
        <WorkspaceEditor />
      </App>,
      {
        pathname: '/monalisa/smile/pull/1/edit/new',
        routePayload,
      },
    )

    // save a file
    await user.type(screen.getByPlaceholderText('Name your file...'), 'my/new/file.txt')
    await user.click(screen.getByText('Save'))
    await user.click(screen.getByText('All files in this repository'))
    await user.click(screen.getByText('Files in this pull request'))

    // confirm that the file tree gets the updated file
    await waitFor(() => {
      expect(screen.getByText('file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    })
    expect(screen.getByText('my/new', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
  })
})

test('renaming file updates file tree', async () => {
  const routePayload = getWorkspaceEditorRoutePayload({path: 'readme'})
  const {user} = render(
    <App>
      <WorkspaceEditor />
    </App>,
    {
      pathname: '/monalisa/smile/pull/1/edit/file/readme',
      routePayload,
    },
  )

  // rename a file
  await user.click(screen.getByLabelText('More file options'))
  await user.click(screen.getByText('Rename file'))
  const renameInput = screen.getByPlaceholderText('Name your file...')
  await user.clear(renameInput)
  await user.type(renameInput, 'new-file.txt')
  await user.click(screen.getByText('Save'))

  // confirm that the file tree gets the updated file
  expect(screen.getByText('new-file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
  // and the old file remains as a deleted file
  expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
  expect(navigateFn).toHaveBeenCalledWith('/monalisa/smile/pull/1/edit/file/new-file.txt')
  expect(navigateFn).toHaveBeenCalledTimes(1)
})

describe('file tree state', () => {
  test('adding file to subdirectory with all files in tree', async () => {
    const readme: DirectoryItem = {
      name: 'readme',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'readme',
    }

    const subdirectory: DirectoryItem = {
      name: 'directory',
      contentType: 'directory',
      hasSimplifiedPath: false,
      path: 'directory',
    }

    const fileTreeData = {
      '': {items: [readme, subdirectory], totalCount: 2},
      directory: {
        items: [
          {
            name: 'readme',
            contentType: 'file',
            hasSimplifiedPath: false,
            path: 'directory/readme',
          },
        ],
        totalCount: 1,
      },
    } as ReposFileTreeData
    const routePayload = getWorkspaceEditorRoutePayload({
      path: '',
      diffPaths: fileTreeData,
      fileTree: fileTreeData,
      isNewFilePage: true,
    })

    const {user} = render(
      <App>
        <WorkspaceEditor />
      </App>,
      {
        pathname: '/monalisa/smile/pull/1/edit/new',
        routePayload,
      },
    )

    // expand the directory
    await user.click(screen.getByText('directory'))

    // add a file for the expanded subdirectory
    await user.type(screen.getByPlaceholderText('Name your file...'), 'directory/file.txt')
    await user.click(screen.getByText('Save'))

    // confirm that the file tree gets updated correctly
    expect(screen.getByText('file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(screen.getAllByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'}).length).toBe(2)
    expect(screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()

    // switch to the PR files tab and confirm that the file tree gets updated correctly
    await user.click(screen.getByText('All files in this repository'))
    await user.click(screen.getByText('Files in this pull request'))

    // confirm that the file tree gets updated correctly
    expect(screen.getByText('file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(screen.getAllByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'}).length).toBe(2)
    expect(screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
  })

  test('adding file to subdirectory with PR files in tree', async () => {
    const readme: DirectoryItem = {
      name: 'readme',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'readme',
    }

    const subdirectory: DirectoryItem = {
      name: 'directory',
      contentType: 'directory',
      hasSimplifiedPath: false,
      path: 'directory',
    }

    const fileTreeData = {
      '': {items: [readme, subdirectory], totalCount: 2},
      directory: {
        items: [
          {
            name: 'readme',
            contentType: 'file',
            hasSimplifiedPath: false,
            path: 'directory/readme',
          },
        ],
        totalCount: 1,
      },
    } as ReposFileTreeData

    const routePayload = getWorkspaceEditorRoutePayload({
      path: '',
      diffPaths: fileTreeData,
      fileTree: fileTreeData,
      isNewFilePage: true,
    })
    const {user} = render(
      <App>
        <WorkspaceEditor />
      </App>,
      {
        pathname: '/monalisa/smile/pull/1/edit/new',
        routePayload,
      },
    )

    // switch to the PR files tab
    await user.click(screen.getByText('All files in this repository'))
    await user.click(screen.getByText('Files in this pull request'))

    // add a file for the expanded subdirectory
    await user.type(screen.getByPlaceholderText('Name your file...'), 'directory/file.txt')
    await user.click(screen.getByText('Save'))

    // confirm that the file tree gets updated correctly
    expect(screen.getByText('file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(screen.getAllByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'}).length).toBe(2)
    expect(screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()

    // switch to the all files tab and confirm that the file tree gets updated correctly
    await user.click(screen.getByText('Files in this pull request'))
    await user.click(screen.getByText('All files in this repository'))

    // confirm that the file tree gets updated correctly
    expect(screen.getByText('file.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(screen.getAllByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'}).length).toBe(2)
    expect(screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
  })

  test('resetting local changes updates file tree correctly', async () => {
    const subdirectory: DirectoryItem = {
      name: 'directory',
      contentType: 'directory',
      hasSimplifiedPath: false,
      path: 'directory',
    }

    const readme: DirectoryItem = {
      name: 'readme',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'readme',
    }

    const deletedFile: DirectoryItem = {
      name: 'deletedfile.txt',
      contentType: 'file',
      hasSimplifiedPath: false,
      path: 'deletedfile.txt',
    }

    const fileTreeData = {
      '': {items: [readme, deletedFile, subdirectory], totalCount: 3},
      directory: {
        items: [
          {
            name: 'newfile.txt',
            contentType: 'file',
            hasSimplifiedPath: false,
            path: 'directory/newfile.txt',
          },
        ],
        totalCount: 1,
      },
    } as ReposFileTreeData

    const routePayload = getWorkspaceEditorRoutePayload({
      diffPaths: fileTreeData,
      fileTree: fileTreeData,
      path: 'directory/newfile.txt',
      fileStatuses: {'deletedfile.txt': 'M'},
    })

    const serializedLocalStorageData = `{"sessionId":"","latestTimestamp":1729540909211,"diffs":[{"path":"directory/newfile.txt","currentFileStatus":"A","originalFileStatus":"A","diff":{"oldFileName":"","newFileName":"directory/newfile.txt","hunks":[],"isDeleted":false,"ignoreReason":null}},{"path":"deletedfile.txt","currentFileStatus":"D","originalFileStatus":"M","diff":{"oldFileName":"deletedfile.txt","newFileName":"","hunks":[{"oldStart":1,"oldLines":1,"newStart":1,"newLines":0,"lines":["-# typed: true"],"linedelimiters":[]}],"isDeleted":true,"ignoreReason":null}}]}`
    localStorage.setItem(
      `hadron-editor-file-deltas-v2/${routePayload.repo.ownerLogin}/${routePayload.repo.name}/1`,
      serializedLocalStorageData,
    )

    const {user} = render(
      <App>
        <WorkspaceEditor />
      </App>,
      {
        pathname: '/monalisa/smile/pull/1/edit/file/directory/newfile.txt',
        routePayload,
      },
    )

    expect(screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(
      screen.getByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).toBeInTheDocument()
    expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(
      screen.getByText('deletedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).toBeInTheDocument()
    // eslint-disable-next-line testing-library/no-node-access
    const deletedFileIcon = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-danger')
    expect(deletedFileIcon).toBeInTheDocument()

    // reset local changes
    await user.click(screen.getByRole('button', {name: 'Commit changes'}))
    await user.click(screen.getByText('Reset all changes'))
    await user.click(screen.getByText('Yes, reset'))

    expect(
      screen.queryByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).not.toBeInTheDocument()
    expect(
      screen.queryByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).not.toBeInTheDocument()
    expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(
      screen.getByText('deletedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).toBeInTheDocument()
    // eslint-disable-next-line testing-library/no-node-access
    const deletedFileIcon2 = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-danger')
    expect(deletedFileIcon2).not.toBeInTheDocument()
    // eslint-disable-next-line testing-library/no-node-access
    const modifiedFileIcon = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-attention')
    expect(modifiedFileIcon).toBeInTheDocument()

    // switch to repos file tree and verify
    await user.click(screen.getByText('Files in this pull request'))
    await user.click(screen.getByText('All files in this repository'))

    expect(
      screen.queryByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).not.toBeInTheDocument()
    expect(
      screen.queryByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).not.toBeInTheDocument()
    expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
    expect(
      screen.getByText('deletedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
    ).toBeInTheDocument()
    // eslint-disable-next-line testing-library/no-node-access
    const deletedFileIcon3 = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-danger')
    expect(deletedFileIcon3).not.toBeInTheDocument()
    // eslint-disable-next-line testing-library/no-node-access
    const modifiedFileIcon2 = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-attention')
    expect(modifiedFileIcon2).toBeInTheDocument()
  })

  describe('deleting', () => {
    test('existing file from subdirectory', async () => {
      const readme: DirectoryItem = {
        name: 'readme',
        contentType: 'file',
        hasSimplifiedPath: false,
        path: 'readme',
      }

      const subdirectory: DirectoryItem = {
        name: 'directory',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'directory',
      }

      const fileTreeData = {
        '': {items: [readme, subdirectory], totalCount: 2},
        directory: {
          items: [
            {
              name: 'nestedfile.txt',
              contentType: 'file',
              hasSimplifiedPath: false,
              path: 'directory/nestedfile.txt',
            },
          ],
          totalCount: 1,
        },
      } as ReposFileTreeData
      const routePayload = getWorkspaceEditorRoutePayload({
        diffPaths: fileTreeData,
        fileTree: fileTreeData,
        path: 'directory/nestedfile.txt',
      })

      const {user} = render(
        <App>
          <WorkspaceEditor />
        </App>,
        {
          pathname: '/monalisa/smile/pull/1/edit/file/directory/nestedfile.txt',
          routePayload,
        },
      )

      // switch to the all files tree
      await user.click(screen.getByText('Files in this pull request'))
      await user.click(screen.getByText('All files in this repository'))

      // confirm original state
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()

      // delete the file
      await user.click(screen.getByLabelText('More file options'))
      await user.click(screen.getByText('Delete file'))
      await user.click(screen.getByText('Yes, delete'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      // eslint-disable-next-line testing-library/no-node-access
      const deletedFileIcon = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-danger')
      expect(deletedFileIcon).toBeInTheDocument()

      // switch to PR files tree and verify
      await user.click(screen.getByText('All files in this repository'))
      await user.click(screen.getByText('Files in this pull request'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      // eslint-disable-next-line testing-library/no-node-access
      const deletedFileIcon2 = document.querySelector('.PRIVATE_TreeView-item-visual > .color-fg-danger')
      expect(deletedFileIcon2).toBeInTheDocument()
    })

    test('locally added file from subdirectory with existing file', async () => {
      const readme: DirectoryItem = {
        name: 'readme',
        contentType: 'file',
        hasSimplifiedPath: false,
        path: 'readme',
      }

      const subdirectory: DirectoryItem = {
        name: 'directory',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'directory',
      }

      const fileTreeData = {
        '': {items: [readme, subdirectory], totalCount: 2},
        directory: {
          items: [
            {
              name: 'newfile.txt',
              contentType: 'file',
              hasSimplifiedPath: false,
              path: 'directory/newfile.txt',
            },
            {
              name: 'nestedfile.txt',
              contentType: 'file',
              hasSimplifiedPath: false,
              path: 'directory/nestedfile.txt',
            },
          ],
          totalCount: 2,
        },
      } as ReposFileTreeData
      const routePayload = getWorkspaceEditorRoutePayload({
        diffPaths: fileTreeData,
        fileTree: fileTreeData,
        path: 'directory/newfile.txt',
      })

      const serializedLocalStorageData = `{"sessionId":"","latestTimestamp":1729540909211,"diffs":[{"path":"directory/newfile.txt","currentFileStatus":"A","originalFileStatus":"A","diff":{"oldFileName":"","newFileName":"directory/newfile.txt","hunks":[],"isDeleted":false,"ignoreReason":null}}]}`
      localStorage.setItem(
        `hadron-editor-file-deltas-v2/${routePayload.repo.ownerLogin}/${routePayload.repo.name}/1`,
        serializedLocalStorageData,
      )

      const {user} = render(
        <App>
          <WorkspaceEditor />
        </App>,
        {
          pathname: '/monalisa/smile/pull/1/edit/file/directory/newfile.txt',
          routePayload,
        },
      )

      // switch to the all files tree
      await user.click(screen.getByText('Files in this pull request'))
      await user.click(screen.getByText('All files in this repository'))

      // confirm original state
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(
        screen.getByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()

      // delete the file
      await user.click(screen.getByLabelText('More file options'))
      await user.click(screen.getByText('Delete file'))
      await user.click(screen.getByText('Yes, delete'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(
        screen.queryByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).not.toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()

      // switch to PR files tree and verify
      await user.click(screen.getByText('All files in this repository'))
      await user.click(screen.getByText('Files in this pull request'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(
        screen.queryByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).not.toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
    })

    test('locally added file from subdirectory without existing file', async () => {
      const readme: DirectoryItem = {
        name: 'readme',
        contentType: 'file',
        hasSimplifiedPath: false,
        path: 'readme',
      }

      const subdirectory: DirectoryItem = {
        name: 'directory',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'directory',
      }

      const fileTreeData = {
        '': {items: [readme, subdirectory], totalCount: 2},
        directory: {
          items: [
            {
              name: 'newfile.txt',
              contentType: 'file',
              hasSimplifiedPath: false,
              path: 'directory/newfile.txt',
            },
          ],
          totalCount: 1,
        },
      } as ReposFileTreeData

      const routePayload = getWorkspaceEditorRoutePayload({
        diffPaths: fileTreeData,
        fileTree: fileTreeData,
        path: 'directory/newfile.txt',
      })

      const serializedLocalStorageData = `{"sessionId":"","latestTimestamp":1729540909211,"diffs":[{"path":"directory/newfile.txt","currentFileStatus":"A","originalFileStatus":"A","diff":{"oldFileName":"","newFileName":"directory/newfile.txt","hunks":[],"isDeleted":false,"ignoreReason":null}}]}`
      localStorage.setItem(
        `hadron-editor-file-deltas-v2/${routePayload.repo.ownerLogin}/${routePayload.repo.name}/1`,
        serializedLocalStorageData,
      )

      const {user} = render(
        <App>
          <WorkspaceEditor />
        </App>,
        {
          pathname: '/monalisa/smile/pull/1/edit/file/directory/newfile.txt',
          routePayload,
        },
      )

      // switch to the all files tree
      await user.click(screen.getByText('Files in this pull request'))
      await user.click(screen.getByText('All files in this repository'))

      // confirm original state
      expect(
        screen.getByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()

      // delete the file
      await user.click(screen.getByLabelText('More file options'))
      await user.click(screen.getByText('Delete file'))
      await user.click(screen.getByText('Yes, delete'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.queryByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).not.toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.queryByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).not.toBeInTheDocument()

      // switch to PR files tree and verify
      await user.click(screen.getByText('All files in this repository'))
      await user.click(screen.getByText('Files in this pull request'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.queryByText('newfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).not.toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.queryByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).not.toBeInTheDocument()
    })
  })

  describe('renaming', () => {
    test('file into existing subdirectory', async () => {
      const readme: DirectoryItem = {
        name: 'readme',
        contentType: 'file',
        hasSimplifiedPath: false,
        path: 'readme',
      }

      const subdirectory: DirectoryItem = {
        name: 'directory',
        contentType: 'directory',
        hasSimplifiedPath: false,
        path: 'directory',
      }

      const fileTreeData = {
        '': {items: [readme, subdirectory], totalCount: 2},
        directory: {
          items: [
            {
              name: 'nestedfile.txt',
              contentType: 'file',
              hasSimplifiedPath: false,
              path: 'directory/nestedfile.txt',
            },
          ],
          totalCount: 1,
        },
      } as ReposFileTreeData
      const routePayload = getWorkspaceEditorRoutePayload({
        diffPaths: fileTreeData,
        fileTree: fileTreeData,
        path: 'readme',
      })

      const {user} = render(
        <App>
          <WorkspaceEditor />
        </App>,
        {
          pathname: '/monalisa/smile/pull/1/edit/file/readme',
          routePayload,
        },
      )

      // switch to the all files tree
      await user.click(screen.getByText('Files in this pull request'))
      await user.click(screen.getByText('All files in this repository'))

      // confirm original state
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(screen.getByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toBeInTheDocument()
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()

      // rename the file
      await user.click(screen.getByLabelText('More file options'))
      await user.click(screen.getByText('Rename file'))
      const renameInput = screen.getByPlaceholderText('Name your file...')
      await user.clear(renameInput)
      await user.type(renameInput, 'directory/readme')
      await user.click(screen.getByText('Save'))

      // confirm that the file tree gets updated correctly
      expect(
        screen.getByText('nestedfile.txt', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
      expect(screen.getAllByText('readme', {selector: '.PRIVATE_TreeView-item-content-text > span'})).toHaveLength(2)
      expect(
        screen.getByText('directory', {selector: '.PRIVATE_TreeView-item-content-text > span'}),
      ).toBeInTheDocument()
    })
  })
})

test('copy file contents', async () => {
  const routePayload = getWorkspaceEditorRoutePayload({path: 'readme', blobContents: 'Hello World!'})
  const {user} = render(
    <App>
      <WorkspaceEditor />
    </App>,
    {
      pathname: '/monalisa/smile/pull/1/edit/file/readme',
      routePayload,
    },
  )

  await user.click(screen.getByLabelText('More file options'))
  await user.click(screen.getByText('Copy file contents'))

  await expect(navigator.clipboard.readText()).resolves.toEqual('Hello World!')
})
