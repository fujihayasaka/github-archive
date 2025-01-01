// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {copilotBotLogin, copilotSearchLogin} from '@github-ui/assignees/copilot-user'
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {Assignee} from '@github-ui/item-picker/AssigneePicker'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderHook} from '@github-ui/react-core/test-utils'
import {useEffect} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useAssigneesQuery} from '../use-assignees-query'
import {useDraftIssueAssignees} from '../use-draft-issue-assignees'

jest.mock('../use-assignees-query', () => ({
  useAssigneesQuery: jest.fn().mockReturnValue({
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

let newIssue: DraftIssue

const REQ_USER_LOGINS = ['monalisa', copilotSearchLogin, 'hubot']
const RESP_USERS: Assignee[] = [
  {
    __typename: '',
    id: '',
    login: 'monalisa',
    name: '',
    avatarUrl: '',
    profileResourcePath: '',
  },
  {
    __typename: '',
    id: '',
    login: copilotBotLogin,
    name: '',
    avatarUrl: '',
    profileResourcePath: '',
  },
  {
    __typename: '',
    id: '',
    login: 'hubot',
    name: '',
    avatarUrl: '',
    profileResourcePath: '',
  },
]

function createProvider(overrides?: Partial<RepositoryPickerRepository$data>) {
  const preselectedData = {
    repository: {
      owner: {login: 'monalisa'},
      name: 'smile',
      viewerIssueCreationPermissions: {
        assignable: true,
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

describe('useDraftIssueAssignees', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    newIssue = createNewIssue()
  })

  it('sends empty array when no initAssignees are provided', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    newIssue.assignees = []
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({assignees: []})
  })

  it('sends empty array when initAssignees cannot be found', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    newIssue.assignees = REQ_USER_LOGINS
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({assignees: []})
  })

  it('does not call onChange while resolving assignees', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createProvider()

    newIssue.assignees = REQ_USER_LOGINS
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not call onChange when repository has not been resolved', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createUndefinedRepoProvider()

    newIssue.assignees = REQ_USER_LOGINS
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('sends list of resolved assignees', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: RESP_USERS,
    })

    const wrapper = createProvider()

    newIssue.assignees = REQ_USER_LOGINS
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({assignees: newIssue.assignees})
  })

  it('sends empty array when user lacks necessary permission', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: RESP_USERS,
    })

    const wrapper = createProvider({
      viewerIssueCreationPermissions: {
        assignable: false,
      },
    } as Partial<RepositoryPickerRepository$data>)

    newIssue.assignees = REQ_USER_LOGINS
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({assignees: []})
  })

  it('sends selected assignees when changed in context', () => {
    ;(useAssigneesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    function Inner({children}: {children: React.ReactNode}) {
      const {setAssignees} = useIssueCreateDataContext()
      useEffect(() => setAssignees(RESP_USERS), [setAssignees])

      return <>{children}</>
    }

    const wrapper = ({children}: {children: React.ReactNode}) => (
      <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={undefined}>
        <Inner>{children}</Inner>
      </IssueCreateContextProvider>
    )

    newIssue.assignees = []
    renderHook(() => useDraftIssueAssignees(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({assignees: REQ_USER_LOGINS})
  })
})
