import {IssueCreateDataContextProvider, type IssueCreateDataProviderProps} from './IssueCreateDataContext'
import {IssueCreateConfigContextProvider, type IssueCreateConfigProviderProps} from './IssueCreateConfigContext'

export type IssueCreateProviderProps = IssueCreateDataProviderProps & IssueCreateConfigProviderProps

export function IssueCreateContextProvider({children, ...props}: IssueCreateProviderProps) {
  return (
    <IssueCreateConfigContextProvider {...props}>
      <IssueCreateDataContextProvider {...props}>{children}</IssueCreateDataContextProvider>
    </IssueCreateConfigContextProvider>
  )
}
