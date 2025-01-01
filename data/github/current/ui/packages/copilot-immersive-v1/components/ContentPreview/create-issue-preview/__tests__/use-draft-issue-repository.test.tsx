// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderHook} from '@github-ui/react-core/test-utils'
import {type ReactNode, useEffect} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useDraftIssueRepository} from '../use-draft-issue-repository'

const onChange = jest.fn()
jest.mock('../use-on-change-callback', () => ({
  useOnChangeCallback: jest.fn().mockImplementation(() => onChange),
}))

function createDraftIssue(overrides?: Partial<DraftIssue>): DraftIssue {
  return {
    id: 'new-issue:test-id#1',
    labels: [],
    tag: 'test-id',
    assignees: [],
    projects: [],
    type: 'new-issue',
    isUserEdited: false,
    messageId: '0',
    name: 'test-name',
    ...overrides,
  }
}

function withRepositoryContext({
  initial,
  selected,
}: {
  initial: RepositoryPickerRepository$data | undefined
  selected?: RepositoryPickerRepository$data
}) {
  function FakeRepositoryPicker({children}: {children: React.ReactNode}) {
    const {setRepository} = useIssueCreateDataContext()
    useEffect(() => setRepository(selected), [setRepository])

    return <>{children}</>
  }

  const f = ({children}: {children: React.ReactNode}) => (
    <IssueCreateContextProvider
      optionConfig={getSafeConfig({})}
      preselectedData={{
        repository: initial,
      }}
    >
      {selected == null ? children : <FakeRepositoryPicker>{children}</FakeRepositoryPicker>}
    </IssueCreateContextProvider>
  )
  return f
}

let repositoryContextWrapper: (props: {children: ReactNode}) => ReactNode

describe('useDraftIssueRepository', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('when no repository was initial set in context, and repository changes through resolvedDraftIssueRepo prop', () => {
    beforeEach(() => {
      repositoryContextWrapper = withRepositoryContext({initial: undefined})
    })

    it('does not call on change when loading draft issue repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = undefined
      const loadingDraftIssueRepo = true
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).not.toHaveBeenCalled()
    })

    it('calls onChange with resolved draft issue repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = {
        id: 'test-initial-repo-id',
        nameWithOwner: 'github/initial-repo',
      } as RepositoryPickerRepository$data
      const loadingDraftIssueRepo = false
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: 'github/initial-repo'}, true)
    })

    it('calls onChange with top repo if failed to resolve draft issue repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = undefined
      const loadingDraftIssueRepo = false
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: 'github/top-repo'}, true)
    })

    it('does not call on change when failed to resolved draft issue and no top repos available', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = undefined
      const loadingDraftIssueRepo = false
      const topRepos = [] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).not.toHaveBeenCalled()
    })
  })

  describe('when no repository was initial set in context, and repository changes through repository picker', () => {
    beforeEach(() => {
      repositoryContextWrapper = withRepositoryContext({
        initial: undefined,
        selected: {
          id: 'test-selected-repo-id',
          nameWithOwner: 'github/selected-repo',
        } as RepositoryPickerRepository$data,
      })
    })

    it('calls onChange with selected repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = {
        id: 'test-initial-repo-id',
        nameWithOwner: 'github/initial-repo',
      } as RepositoryPickerRepository$data
      const loadingDraftIssueRepo = false
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: 'github/selected-repo'}, false)
    })
  })

  describe('when repository was initial set in context, and repository changes through resolvedDraftIssueRepo prop', () => {
    beforeEach(() => {
      repositoryContextWrapper = withRepositoryContext({
        initial: {
          id: 'test-initial-repo-id',
          nameWithOwner: 'github/initial-repo',
        } as RepositoryPickerRepository$data,
      })
    })

    it('does not call on change when loading draft issue repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = undefined
      const loadingDraftIssueRepo = true
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).not.toHaveBeenCalled()
    })

    it('calls onChange even if resolved to the same repository', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = {
        id: 'test-initial-repo-id',
        nameWithOwner: 'github/initial-repo',
      } as RepositoryPickerRepository$data
      const loadingDraftIssueRepo = false
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: 'github/initial-repo'}, true)
    })

    it('calls on change with undefined when failed to resolved draft issue and no top repos available', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = undefined
      const loadingDraftIssueRepo = false
      const topRepos = [] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: undefined}, true)
    })

    it('calls onChange with top repo if failed to resolve draft issue repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = undefined
      const loadingDraftIssueRepo = false
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: 'github/top-repo'}, true)
    })
  })

  describe('when repository was initial set in context, and repository changes through repository picker', () => {
    beforeEach(() => {
      repositoryContextWrapper = withRepositoryContext({
        initial: {
          id: 'test-initial-repo-id',
          nameWithOwner: 'github/initial-repo',
        } as RepositoryPickerRepository$data,
        selected: {
          id: 'test-selected-repo-id',
          nameWithOwner: 'github/selected-repo',
        } as RepositoryPickerRepository$data,
      })
    })

    it('calls onChange with selected repo', () => {
      const draftIssue = createDraftIssue()
      const resolvedDraftIssueRepo = {
        id: 'test-initial-repo-id',
        nameWithOwner: 'github/initial-repo',
      } as RepositoryPickerRepository$data
      const loadingDraftIssueRepo = false
      const topRepos = [{id: 'test-top-repo-id', nameWithOwner: 'github/top-repo'}] as RepositoryPickerRepository$data[]

      renderHook(() => useDraftIssueRepository(draftIssue, resolvedDraftIssueRepo, loadingDraftIssueRepo, topRepos), {
        wrapper: repositoryContextWrapper,
      })

      expect(onChange).toHaveBeenCalledWith({repository: 'github/selected-repo'}, false)
    })
  })
})
