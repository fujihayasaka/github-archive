import {createContext, useContext, useMemo} from 'react'

export type IssueCreateInitialValuesState = {
  title?: string
  body?: string
  repository?: string
  owner?: string
  template?: string
  labels?: string[]
  assignees?: string[]
  projects?: string[]
  milestone?: string
  issueType?: string
}

const IssueCreateInitialValuesContext = createContext<IssueCreateInitialValuesState | null>(null)

type IssueCreateInitialValuesContextProviderProps = React.PropsWithChildren<IssueCreateInitialValuesState>

export function IssueCreateInitialValuesContextProvider({
  title,
  body,
  repository,
  owner,
  template,
  labels,
  assignees,
  projects,
  milestone,
  issueType,
  children,
}: IssueCreateInitialValuesContextProviderProps) {
  const contextValue: IssueCreateInitialValuesState = useMemo(() => {
    return {
      title,
      body,
      repository,
      owner,
      template,
      labels,
      assignees,
      projects,
      milestone,
      issueType,
    }
  }, [title, body, repository, owner, template, labels, assignees, projects, milestone, issueType])

  return (
    <IssueCreateInitialValuesContext.Provider value={contextValue}>{children}</IssueCreateInitialValuesContext.Provider>
  )
}

export const useIssueCreateInitialValuesContext = () => {
  const context = useContext(IssueCreateInitialValuesContext)
  if (!context) {
    return {}
  }

  return context
}
