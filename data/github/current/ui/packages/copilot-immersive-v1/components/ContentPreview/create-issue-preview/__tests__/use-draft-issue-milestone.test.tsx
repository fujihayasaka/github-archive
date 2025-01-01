// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {Milestone} from '@github-ui/item-picker/MilestonePicker'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderHook} from '@github-ui/react-core/test-utils'
import {useEffect} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useDraftIssueMilestone} from '../use-draft-issue-milestone'
import {useMilestoneQuery} from '../use-milestone-query'

jest.mock('../use-milestone-query', () => ({
  useMilestoneQuery: jest.fn().mockReturnValue({
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

const MILESTONES: Milestone[] = ['v1.0', 'v1.1', 'v2.0'].map(name => ({
  title: name,
  id: '',
  url: '',
  progressPercentage: 0,
  dueOn: '',
  closed: false,
  closedAt: '',
  ' $fragmentType': 'MilestonePickerMilestone',
}))

function createProvider(overrides?: Partial<RepositoryPickerRepository$data>) {
  const preselectedData = {
    repository: {
      owner: {login: 'monalisa'},
      name: 'smile',
      viewerIssueCreationPermissions: {
        milestoneable: true,
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

describe('useDraftIssueLabels', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    newIssue = createNewIssue()
  })

  it('does not update when no initMilestone is provided', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: null,
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not update when initMilestone cannot be found', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: null,
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not update while resolving milestones', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not call onChange when repository has not been resolved', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: MILESTONES[0],
    })

    const wrapper = createUndefinedRepoProvider()

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('sends resolved milestone', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: MILESTONES[0],
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({milestone: MILESTONES[0]!.title})
  })

  it('sends undefined when user lacks necessary permission', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: MILESTONES[0],
    })

    const wrapper = createProvider({
      viewerIssueCreationPermissions: {
        milestoneable: false,
      },
    } as Partial<RepositoryPickerRepository$data>)

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({milestone: undefined})
  })

  it('sends selected milestone when changed in context', () => {
    ;(useMilestoneQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: null,
    })

    function Inner({children}: {children: React.ReactNode}) {
      const {setMilestone} = useIssueCreateDataContext()
      useEffect(() => setMilestone(MILESTONES[0]!), [setMilestone])

      return <>{children}</>
    }

    const wrapper = ({children}: {children: React.ReactNode}) => (
      <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={undefined}>
        <Inner>{children}</Inner>
      </IssueCreateContextProvider>
    )

    renderHook(() => useDraftIssueMilestone(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({milestone: MILESTONES[0]!.title})
  })
})
