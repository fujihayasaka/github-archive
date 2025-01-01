// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {getSafeConfig} from '@github-ui/issue-create/getSafeConfig'
import {IssueCreateContextProvider} from '@github-ui/issue-create/IssueCreateContext'
import {useIssueCreateDataContext} from '@github-ui/issue-create/IssueCreateDataContext'
import type {RepositoryPickerRepository$data} from '@github-ui/item-picker/RepositoryPickerRepository.graphql'
import {renderHook} from '@github-ui/react-core/test-utils'
import {useEffect} from 'react'

import type {DraftIssue} from '../../content-preview-types'
import {useDraftIssueLabels} from '../use-draft-issue-labels'
import {type Label, useLabelsQuery} from '../use-labels-query'

jest.mock('../use-labels-query', () => ({
  useLabelsQuery: jest.fn().mockReturnValue({
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

const LABELS: Label[] = [
  {
    id: '',
    name: 'bug',
    color: '',
    description: undefined,
    nameHTML: '',
    url: '',
    ' $fragmentType': 'LabelPickerLabel',
  },
  {
    id: '',
    name: 'task',
    color: '',
    description: undefined,
    nameHTML: '',
    url: '',
    ' $fragmentType': 'LabelPickerLabel',
  },
  {
    id: '',
    name: 'feature',
    color: '',
    description: undefined,
    nameHTML: '',
    url: '',
    ' $fragmentType': 'LabelPickerLabel',
  },
]

function createProvider(overrides?: Partial<RepositoryPickerRepository$data>) {
  const preselectedData = {
    repository: {
      owner: {login: 'monalisa'},
      name: 'smile',
      viewerIssueCreationPermissions: {
        labelable: true,
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

function createNullRepoProvider() {
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

  it('sends empty array when no initLabels are provided', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({labels: []})
  })

  it('sends empty array when initLabels cannot be found', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    const wrapper = createProvider()

    newIssue.labels = LABELS.map(label => label.name)
    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({labels: []})
  })

  it('does not call onChange while resolving labels', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createProvider()

    newIssue.labels = LABELS.map(label => label.name)

    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('does not call onChange when repository has not been resolved', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: true,
      data: undefined,
    })

    const wrapper = createNullRepoProvider()

    newIssue.labels = LABELS.map(label => label.name)

    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).not.toHaveBeenCalled()
  })

  it('sends list of resolved labels', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: LABELS,
    })

    const wrapper = createProvider()

    newIssue.labels = LABELS.map(label => label.name)
    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({labels: newIssue.labels})
  })

  it('sends empty array when user lacks necessary permissions', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: LABELS,
    })

    const wrapper = createProvider({
      viewerIssueCreationPermissions: {
        labelable: false,
      },
    } as Partial<RepositoryPickerRepository$data>)

    newIssue.labels = LABELS.map(label => label.name)
    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({labels: []})
  })

  it('sends selected labels when changed in context', () => {
    ;(useLabelsQuery as jest.Mock).mockReturnValue({
      isLoading: false,
      data: [],
    })

    function Inner({children}: {children: React.ReactNode}) {
      const {setLabels} = useIssueCreateDataContext()
      useEffect(() => setLabels(LABELS), [setLabels])

      return <>{children}</>
    }

    const wrapper = ({children}: {children: React.ReactNode}) => (
      <IssueCreateContextProvider optionConfig={getSafeConfig({})} preselectedData={undefined}>
        <Inner>{children}</Inner>
      </IssueCreateContextProvider>
    )

    newIssue.labels = []
    renderHook(() => useDraftIssueLabels(newIssue), {wrapper})

    expect(onChange).toHaveBeenCalledWith({labels: LABELS.map(label => label.name)})
  })
})
