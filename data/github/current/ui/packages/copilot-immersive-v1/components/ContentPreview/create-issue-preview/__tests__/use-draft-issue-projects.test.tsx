// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderHook} from '@github-ui/react-core/test-utils'
import {useEffect} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useDraftIssueProjects} from '../use-draft-issue-projects'
import {type Project, useProjectsQuery} from '../use-projects-query'

jest.mock('../use-projects-query', () => ({
  useProjectsQuery: jest.fn().mockReturnValue({
    isLoading: false,
    data: null,
  }),
}))

const onChange = jest.fn()
jest.mock('../use-on-change-callback', () => ({
  useOnChangeCallback: jest.fn().mockImplementation(() => onChange),
}))

function createNewIssue(): DraftIssue {
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
  }
}

function createUndefinedRepoProvider() {
  const preselectedData = {
    repository: undefined,
  }

  const f = ({children}: {children: React.ReactNode}) => (
    <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={preselectedData}>
      {children}
    </IssueCreateContextProvider>
  )
  return f
}

let newIssue: DraftIssue

const PROJECTS: Project[] = ['Roadmap', 'Backlog'].map(name => ({
  title: name,
  id: '',
  number: 1,
  url: '',
  closed: false,
  hasReachedItemsLimit: false,
  viewerCanUpdate: true,
  __typename: 'ProjectV2',
  ' $fragmentType': 'ProjectPickerProject',
}))

function createProvider(overrides?: Partial<RepositoryPickerRepository$data>) {
  const preselectedData = {
    repository: {
      owner: {login: 'monalisa'},
      name: 'smile',
      viewerIssueCreationPermissions: {
        triageable: true,
      },
      ...overrides,
    } as RepositoryPickerRepository$data,
  }

  const f = ({children}: {children: React.ReactNode}) => (
    <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={preselectedData}>
      {children}
    </IssueCreateContextProvider>
  )
  return f
}

describe('useDraftIssueProjects', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    newIssue = createNewIssue()
  })

  it('sends empty array when no initProjects are provided', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    newIssue.projects = []
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({projects: []})
  })

  it('sends empty array when initProjects cannot be found', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    newIssue.projects = PROJECTS.map(project => project.title)
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({projects: []})
  })

  it('does not call onChange while resolving projects', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createProvider()

    newIssue.projects = PROJECTS.map(project => project.title)
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not call onChange when repository has not been resolved', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: PROJECTS,
    })

    const wrapper = createUndefinedRepoProvider()

    newIssue.projects = PROJECTS.map(project => project.title)
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('sends list of resolved projects', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: PROJECTS,
    })

    const wrapper = createProvider()

    newIssue.projects = PROJECTS.map(project => project.title)
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({projects: newIssue.projects})
  })

  it('sends empty array when user lacks necessary permissions', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: PROJECTS,
    })

    const wrapper = createProvider({
      viewerIssueCreationPermissions: {
        triageable: false,
      },
    } as Partial<RepositoryPickerRepository$data>)

    newIssue.projects = PROJECTS.map(project => project.title)
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({projects: []})
  })

  it('sends selected projects when changed in context', () => {
    ;(useProjectsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    function Inner({children}: {children: React.ReactNode}) {
      const {setProjects} = useIssueCreateDataContext()
      useEffect(() => setProjects(PROJECTS), [setProjects])

      return <>{children}</>
    }

    const wrapper = ({children}: {children: React.ReactNode}) => (
      <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={undefined}>
        <Inner>{children}</Inner>
      </IssueCreateContextProvider>
    )

    newIssue.projects = []
    renderHook(() => useDraftIssueProjects(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({projects: PROJECTS.map(project => project.title)})
  })
})
