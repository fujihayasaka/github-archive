import {mockClientEnv} from '@github-ui/client-env/mock'
import {useCopilotChatEntitlement} from '@github-ui/copilot-chat/utils/copilot-chat-entitlement'
import {CopilotLicenseType, CopilotPlan} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {useQuery} from '@github-ui/react-query'
import {act, renderHook} from '@testing-library/react'

import {
  AcaStatus,
  CodespaceStatus,
  EntitledService,
  ErrorType,
  initialState,
  Service,
  Status,
} from '../../utilities/workbench-store-reducer'
import {useGlobalReadOnly, useWorkbenchStore, WorkbenchStoreProvider} from '../WorkbenchStoreContext'

jest.mock('@github-ui/react-query', () => ({
  useQuery: jest.fn(),
}))

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-entitlement', () => ({
  useCopilotChatEntitlement: jest.fn(),
}))

function getWrapper() {
  const wrapper = ({children}: {children: React.ReactNode}) => (
    <AppPayloadContext.Provider value={{...initialState.entitlement[EntitledService.COPILOT]}}>
      <WorkbenchStoreProvider>{children}</WorkbenchStoreProvider>
    </AppPayloadContext.Provider>
  )
  return wrapper
}

function render() {
  const wrapper = getWrapper()
  return {
    workbenchStoreHook: renderHook(() => useWorkbenchStore(), {wrapper}),
    readOnlyHook: renderHook(() => useGlobalReadOnly(), {wrapper}),
  }
}

function renderUseGlobalReadOnly() {
  const {readOnlyHook} = render()
  return readOnlyHook
}

function renderUseWorkbenchStore() {
  const {workbenchStoreHook} = render()
  return workbenchStoreHook
}

const mockUseQuery = useQuery as jest.Mock
const mockUseCopilotChatEntitlement = useCopilotChatEntitlement as jest.Mock

describe('WorkbenchStoreContext', () => {
  // Setup mocks for dependencies
  beforeEach(() => {
    mockUseQuery.mockReturnValue({
      data: initialState.entitlement,
    })
    mockUseCopilotChatEntitlement.mockReturnValue([null, jest.fn()])
  })

  it('should always return readOnly as false when the feature flag is not enabled', () => {
    const {result} = renderUseWorkbenchStore()
    act(() => {
      result.current.setReadOnly(true)
    })
    expect(result.current.readOnly).toBe(false)
  })

  describe('with FF enabled', () => {
    beforeEach(() => {
      mockClientEnv({
        featureFlags: ['workbench_store_readonly'],
      })
    })

    describe('useGlobalReadOnly', () => {
      it('should return a boolean', () => {
        const {
          result: {current: globalReadOnly},
        } = renderUseGlobalReadOnly()

        expect(globalReadOnly).toBe(false)
      })
    })

    describe('useWorkbenchStore', () => {
      it('provides default readOnly, errors, status, and entitlement state', () => {
        const {
          result: {
            current: {status, entitlement, readOnly, errors},
          },
        } = renderUseWorkbenchStore()

        expect(readOnly).toBe(false)
        expect(errors).toEqual([])
        expect(status[Service.CODESPACE]).toBe(Status.DISCONNECTED)
        expect(status[Service.VITE]).toBe(Status.DISCONNECTED)
        expect(status[Service.AGENT]).toBe(Status.DISCONNECTED)
        expect(status[Service.FILE_SYNCER]).toBe(Status.DISCONNECTED)
        expect(status[Service.DESIGNER]).toBe(Status.DISCONNECTED)
        expect(status[Service.ACA]).toBe(AcaStatus.RESOURCES_CREATED)
        expect(status[Service.COPILOT]).toBe(Status.CONNECTED)
        expect(entitlement[EntitledService.COPILOT]).toBeDefined()
        expect(entitlement[EntitledService.COPILOT].plan).toBe(CopilotPlan.IndividualFree)
        expect(entitlement[EntitledService.COPILOT].licenseType).toBe(CopilotLicenseType.LicensedLimited)
        expect(entitlement[EntitledService.CODESPACE_COMPUTE]).toBeDefined()
        expect(entitlement[EntitledService.CODESPACE_COMPUTE].allowed).toBe(false)
        expect(entitlement[EntitledService.CODESPACE_SESSIONS]).toBeDefined()
        expect(entitlement[EntitledService.CODESPACE_SESSIONS].allowed).toBe(true)
      })

      it('setReadOnly', () => {
        const {result} = renderUseWorkbenchStore()
        expect(result.current.readOnly).toBe(false)
        act(() => {
          result.current.setReadOnly(true)
        })
        expect(result.current.readOnly).toBe(true)
        act(() => {
          result.current.setReadOnly(false)
        })
        expect(result.current.readOnly).toBe(false)
      })

      it('onError', () => {
        const {result} = renderUseWorkbenchStore()
        expect(result.current.errors).toEqual([])
        act(() => {
          result.current.onError({
            service: Service.CODESPACE,
            type: ErrorType.UNKNOWN,
          })
        })
        expect(result.current.errors).toEqual([
          {
            service: Service.CODESPACE,
            type: ErrorType.UNKNOWN,
          },
        ])
        expect(result.current.status[Service.CODESPACE]).toEqual(Status.ERROR)
      })

      it('onConnected', () => {
        const {result} = renderUseWorkbenchStore()
        act(() => {
          result.current.onConnected({
            service: Service.AGENT,
          })
        })
        expect(result.current.status[Service.AGENT]).toEqual(Status.CONNECTED)
      })

      it('onDisconnected', () => {
        const {result} = renderUseWorkbenchStore()
        act(() => {
          result.current.onConnected({
            service: Service.VITE,
          })
        })
        act(() => {
          result.current.onDisconnected({
            service: Service.VITE,
          })
        })
        expect(result.current.status[Service.VITE]).toEqual(Status.DISCONNECTED)
      })

      it('onIdle', () => {
        const {result} = renderUseWorkbenchStore()
        act(() => {
          result.current.onIdle({
            service: Service.COPILOT,
          })
        })
        expect(result.current.status[Service.COPILOT]).toEqual(Status.IDLE)
      })

      it('onStatus', () => {
        const {result} = renderUseWorkbenchStore()
        act(() => {
          result.current.onStatus({
            service: Service.ACA,
            status: AcaStatus.RESOURCES_CREATED,
          })
        })
        expect(result.current.status[Service.ACA]).toEqual(AcaStatus.RESOURCES_CREATED)
      })

      it('onCodespaceStatus', () => {
        const {result} = renderUseWorkbenchStore()
        act(() => {
          result.current.onCodespaceStatus('creating')
        })
        expect(result.current.status[Service.CODESPACE]).toEqual(CodespaceStatus.STARTING)
        act(() => {
          result.current.onCodespaceStatus('starting')
        })
        expect(result.current.status[Service.CODESPACE]).toEqual(CodespaceStatus.STARTING)
        act(() => {
          result.current.onCodespaceStatus('failed')
        })
        expect(result.current.status[Service.CODESPACE]).toEqual(Status.ERROR)
        act(() => {
          result.current.onCodespaceStatus('none')
        })
        expect(result.current.status[Service.CODESPACE]).toEqual(Status.DISCONNECTED)
      })

      it('onSuccess', () => {
        const {result} = renderUseWorkbenchStore()
        act(() => {
          result.current.onError({
            service: Service.VITE,
            type: ErrorType.UNKNOWN,
          })
        })
        expect(result.current.status[Service.VITE]).toEqual(Status.ERROR)
        expect(result.current.errors.filter(error => error.service === Service.VITE).length).toEqual(1)
        act(() => {
          result.current.onSuccess({
            service: Service.VITE,
          })
        })
        expect(result.current.status[Service.VITE]).toEqual(Status.CONNECTED)
        expect(result.current.errors.filter(error => error.service === Service.VITE).length).toEqual(0)
      })
    })
  })
})
