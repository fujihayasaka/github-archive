// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {IssueType} from '@github-ui/item-picker/IssueTypePicker'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderHook} from '@github-ui/react-core/test-utils'
import {useEffect} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useDraftIssueType} from '../use-draft-issue-type'
import {useIssueTypesQuery} from '../use-issue-types-query'

jest.mock('../use-issue-types-query', () => ({
  useIssueTypesQuery: jest.fn().mockReturnValue({
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

const ISSUE_TYPES: IssueType[] = [
  {
    color: 'GREEN',
    description: '',
    id: '',
    isEnabled: true,
    name: 'Feature',
    ' $fragmentType': 'IssueTypePickerIssueType',
  },
  {
    color: 'BLUE',
    description: '',
    id: '',
    isEnabled: true,
    name: 'Task',
    ' $fragmentType': 'IssueTypePickerIssueType',
  },
  {
    color: 'RED',
    description: '',
    id: '',
    isEnabled: true,
    name: 'Bug',
    ' $fragmentType': 'IssueTypePickerIssueType',
  },
]

function createProvider(overrides?: Partial<RepositoryPickerRepository$data>) {
  const preselectedData = {
    repository: {
      owner: {login: 'monalisa'},
      name: 'smile',
      viewerIssueCreationPermissions: {
        typeable: true,
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

describe('useDraftIssueLabels', () => {
  beforeEach(() => {
    jest.clearAllMocks()
    newIssue = createNewIssue()
  })

  it('does not update when no initIssueType is provided', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not update when initIssueType cannot be found', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not update while resolving issueTypes', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not call onChange when repository has not been resolved', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: ISSUE_TYPES,
    })

    const wrapper = createUndefinedRepoProvider()

    newIssue.issueType = ISSUE_TYPES[0]!.name
    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('sends resolved issueType', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: ISSUE_TYPES,
    })

    const wrapper = createProvider()

    newIssue.issueType = ISSUE_TYPES[0]!.name
    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({issueType: ISSUE_TYPES[0]!.name})
  })

  it('sends undefined when user lacks necessary permission', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: ISSUE_TYPES,
    })

    const wrapper = createProvider({
      viewerIssueCreationPermissions: {
        typeable: false,
      },
    } as Partial<RepositoryPickerRepository$data>)

    newIssue.issueType = ISSUE_TYPES[0]!.name
    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({issueType: undefined})
  })

  it('sends selected issueType when changed in context', () => {
    ;(useIssueTypesQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    function Inner({children}: {children: React.ReactNode}) {
      const {setIssueType} = useIssueCreateDataContext()
      useEffect(() => setIssueType(ISSUE_TYPES[0]!), [setIssueType])

      return <>{children}</>
    }

    const wrapper = ({children}: {children: React.ReactNode}) => (
      <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={undefined}>
        <Inner>{children}</Inner>
      </IssueCreateContextProvider>
    )

    renderHook(() => useDraftIssueType(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({issueType: ISSUE_TYPES[0]!.name})
  })
})
