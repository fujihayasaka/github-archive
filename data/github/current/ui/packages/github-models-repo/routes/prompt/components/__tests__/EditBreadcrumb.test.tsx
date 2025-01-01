import type {Repository} from '@github-ui/current-repository'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {EditBreadcrumb, normalizeRelativePathChange} from '../EditBreadcrumb'

describe('EditBreadcrumb', () => {
  const mockRepository: Repository = {
    id: 0,
    name: '',
    ownerLogin: '',
    defaultBranch: '',
    createdAt: '',
    currentUserCanPush: false,
    isFork: false,
    isEmpty: false,
    ownerAvatar: '',
    public: false,
    private: false,
    isOrgOwned: false,
  }

  it('renders initial EditBreadcrumb state', () => {
    const nameInputRef = {current: document.createElement('input')}

    render(<EditBreadcrumb repository={mockRepository} folderPath="/" fileName="" nameInputRef={nameInputRef} />)

    expect(screen.getByText('Prompts')).toBeInTheDocument()
  })

  it('renders folder path as breadcrumbs', () => {
    const nameInputRef = {current: document.createElement('input')}

    render(
      <EditBreadcrumb
        repository={mockRepository}
        folderPath="path/to/folder/"
        fileName="file"
        nameInputRef={nameInputRef}
      />,
    )

    expect(screen.getByText('path')).toBeInTheDocument()
    expect(screen.getByText('to')).toBeInTheDocument()
    expect(screen.getByText('folder')).toBeInTheDocument()
  })
})

describe('normalizeRelativePathChange', () => {
  it('should normalize folder path with ending ../', () => {
    const folderPath = 'path/to/folder/../'
    const normalizedPath = normalizeRelativePathChange(folderPath)
    expect(normalizedPath).toBe('path/to/')
  })

  it('should normalize folder path with ending ../ and only one directory deep', () => {
    const folderPath = 'folder/../'
    const normalizedPath = normalizeRelativePathChange(folderPath)
    expect(normalizedPath).toBe('')
  })

  it('should normalize folder path with only ../', () => {
    const folderPath = '../'
    const normalizedPath = normalizeRelativePathChange(folderPath)
    expect(normalizedPath).toBe('')
  })

  it('should not modify folder path without ../', () => {
    const folderPath = 'path/to/folder/'
    const normalizedPath = normalizeRelativePathChange(folderPath)
    expect(normalizedPath).toBe(folderPath)
  })

  // we only normalize the last part of the path because that is the only part that the user can change
  it('should not normalize folder path with ../ in the middle', () => {
    const folderPath = 'path/to/../folder/'
    const normalizedPath = normalizeRelativePathChange(folderPath)
    expect(normalizedPath).toBe('path/to/../folder/')
  })

  // we only normalize the last part of the path because that is the only part that the user can change
  it('should not normalize folder path with ../ at the beginning', () => {
    const folderPath = '../path/to/folder/'
    const normalizedPath = normalizeRelativePathChange(folderPath)
    expect(normalizedPath).toBe('../path/to/folder/')
  })
})
