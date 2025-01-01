import {render} from '@github-ui/react-core/test-utils'
import type {PropsWithChildren} from 'react'

import {initialState, WorkbenchStoreContext} from '../contexts/WorkbenchStoreContext'

export type WorkbenchStoreProps = Omit<Partial<WorkbenchStoreContext>, 'status' | 'entitlement'> & {
  status?: Partial<WorkbenchStoreContext['status']>
  entitlement?: Partial<WorkbenchStoreContext['entitlement']>
}

export function renderWorkbenchStore(props: PropsWithChildren<WorkbenchStoreProps>) {
  return render(<WorkbenchStoreProvider {...props} />)
}

export function WorkbenchStoreWrapper(props: WorkbenchStoreProps = {}) {
  return function wrapper({children}: {children: React.ReactNode}) {
    return <WorkbenchStoreProvider {...props}>{children}</WorkbenchStoreProvider>
  }
}

export function WorkbenchStoreProvider({
  children,
  status,
  hasServiceErrors = false,
  entitlement,
  readOnly = false,
  ...rest
}: PropsWithChildren<WorkbenchStoreProps>) {
  return (
    <WorkbenchStoreContext.Provider
      value={{
        ...initialState,
        status: {
          ...initialState.status,
          ...(status || {}),
        },
        entitlement: {
          ...initialState.entitlement,
          ...(entitlement || {}),
        },
        hasServiceErrors,
        readOnly: readOnly ?? initialState.readOnly,
        setReadOnly: jest.fn(),
        onError: jest.fn(),
        onConnected: jest.fn(),
        onDisconnected: jest.fn(),
        onIdle: jest.fn(),
        onStatus: jest.fn(),
        onCodespaceStatus: jest.fn(),
        onSuccess: jest.fn(),
        reloadQuota: jest.fn(),
        ...rest,
      }}
    >
      {children}
    </WorkbenchStoreContext.Provider>
  )
}
