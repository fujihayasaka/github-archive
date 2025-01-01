import safeStorage from '@github-ui/safe-storage'
import {BlobService} from '@github-ui/workspace-editor'
import {applyPatch, formatPatch} from 'diff'

import {ReadLocalWorkspaceFileSkill} from '../read-local-workspace-file'

jest.mock('@github-ui/safe-storage')
jest.mock('@github-ui/workspace-editor')
jest.mock('diff')

describe('ReadLocalWorkspaceFileSkill', () => {
  const mockSafeStorage = {
    getItem: jest.fn(),
  }
  const mockFetchJSON = jest.fn()
  const mockApplyPatch = jest.fn()
  const mockFormatPatch = jest.fn()
  const mockGetBlob = jest.fn()

  beforeEach(() => {
    ;(safeStorage as jest.Mock).mockReturnValue(mockSafeStorage)
    ;(BlobService as jest.Mock).mockImplementation(() => ({
      ...jest.requireActual('@github-ui/workspace-editor').BlobService,
      getBlob: mockGetBlob,
    }))
    ;(applyPatch as jest.Mock).mockImplementation(mockApplyPatch)
    ;(formatPatch as jest.Mock).mockImplementation(mockFormatPatch)
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('should validate arguments correctly', () => {
    const skill = new ReadLocalWorkspaceFileSkill(
      '1',
      'read-local-workspace-file',
      JSON.stringify({
        path: './test.txt',
        repository: {ownerLogin: 'owner', name: 'repo'},
        pullRequest: {number: '1', headSHA: 'sha'},
      }),
    )

    const args = skill['validateArgs']()
    expect(args.path).toBe('./test.txt')
    expect(args.repository.ownerLogin).toBe('owner')
    expect(args.repository.name).toBe('repo')
    expect(args.pullRequest.number).toBe('1')
    expect(args.pullRequest.headSHA).toBe('sha')
  })

  it('should handle argument validation errors gracefully', async () => {
    const skill = new ReadLocalWorkspaceFileSkill(
      '1',
      'read-local-workspace-file',
      JSON.stringify({
        repository: {ownerLogin: 'owner', name: 'repo'},
        pullRequest: {number: '1', headSHA: 'sha'},
      }),
    )

    const {result} = await skill.execute()
    expect(result).toEqual('Error: No path found on parsed arguments')
  })

  it('should fetch blob contents correctly', async () => {
    const skill = new ReadLocalWorkspaceFileSkill(
      '1',
      'read-local-workspace-file',
      JSON.stringify({
        path: './test.txt',
        repository: {ownerLogin: 'owner', name: 'repo'},
        pullRequest: {number: '1', headSHA: 'sha'},
      }),
    )

    mockGetBlob.mockResolvedValueOnce({
      ok: true,
      payload: {blobContents: 'file content'},
    })

    const blobContents = await skill['fetchBlob'](
      'test.txt',
      {ownerLogin: 'owner', name: 'repo'},
      {headSHA: 'sha', number: '1'},
    )
    expect(blobContents).toBe('file content')
  })

  it('should return blob contents if no patch is found', async () => {
    const skill = new ReadLocalWorkspaceFileSkill(
      '1',
      'read-local-workspace-file',
      JSON.stringify({
        path: './test.txt',
        repository: {ownerLogin: 'owner', name: 'repo'},
        pullRequest: {number: '1', headSHA: 'sha'},
      }),
    )

    mockGetBlob.mockResolvedValueOnce({
      ok: true,
      payload: {blobContents: 'file content'},
    })

    mockSafeStorage.getItem.mockReturnValueOnce(
      JSON.stringify({
        diffs: [],
        sessionId: '',
        latestTimestamp: 0,
      }),
    )

    const {result} = await skill.execute()
    expect(result).toBe('file content')
  })

  it('should apply patch if found', async () => {
    const skill = new ReadLocalWorkspaceFileSkill(
      '1',
      'read-local-workspace-file',
      JSON.stringify({
        path: './test.txt',
        repository: {ownerLogin: 'owner', name: 'repo'},
        pullRequest: {number: '1', headSHA: 'sha'},
      }),
    )

    mockSafeStorage.getItem.mockReturnValueOnce(
      JSON.stringify({
        diffs: [{path: 'test.txt', diff: {}}],
        sessionId: '',
        latestTimestamp: 0,
      }),
    )

    mockFormatPatch.mockReturnValueOnce('patched content')

    const {result} = await skill.execute()
    expect(result).toBe('patched content')
  })

  it('should handle no patch or local changes gracefully', async () => {
    const skill = new ReadLocalWorkspaceFileSkill(
      '1',
      'read-local-workspace-file',
      JSON.stringify({
        path: './test.txt',
        repository: {ownerLogin: 'owner', name: 'repo'},
        pullRequest: {number: '1', headSHA: 'sha'},
      }),
    )

    mockFetchJSON.mockRejectedValueOnce(new Error('fetch error'))
    mockSafeStorage.getItem.mockReturnValueOnce(JSON.stringify(null))

    const {result} = await skill.execute()
    expect(result).toBe('')
  })
})
