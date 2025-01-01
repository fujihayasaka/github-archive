import {
  AcaStatus,
  AgentStatus,
  CodespaceStatus,
  ErrorType,
  initialState,
  Service,
  Status,
  type WorkbenchStoreAction,
  workbenchStoreReducer,
} from '../workbench-store-reducer'

test('set readOnly: true', () => {
  const action: WorkbenchStoreAction = {type: 'LOCK_READS'}
  const {readOnly} = workbenchStoreReducer(initialState, action)
  expect(readOnly).toBe(true)
})

test('set readOnly: false', () => {
  const action: WorkbenchStoreAction = {type: 'UNLOCK_READS'}
  const {readOnly} = workbenchStoreReducer(initialState, action)
  expect(readOnly).toBe(false)
})

test('set a service as connected', () => {
  const action: WorkbenchStoreAction = {type: 'CONNECTED', payload: {service: Service.DESIGNER}}
  const {status} = workbenchStoreReducer(initialState, action)
  expect(status[Service.DESIGNER]).toBe(Status.CONNECTED)
})

test('set a service as disconnected', () => {
  const action: WorkbenchStoreAction = {type: 'DISCONNECTED', payload: {service: Service.FILE_SYNCER}}
  const {status} = workbenchStoreReducer(initialState, action)
  expect(status[Service.FILE_SYNCER]).toBe(Status.DISCONNECTED)
})

test('set a service as idle', () => {
  const action: WorkbenchStoreAction = {type: 'IDLE', payload: {service: Service.COPILOT}}
  const {status} = workbenchStoreReducer(initialState, action)
  expect(status[Service.COPILOT]).toBe(Status.IDLE)
})

describe('set a service with a service-specific status', () => {
  test('CodespaceStatus', () => {
    const action: WorkbenchStoreAction = {
      type: 'STATUS',
      payload: {service: Service.CODESPACE, status: CodespaceStatus.STARTING},
    }
    const {status} = workbenchStoreReducer(initialState, action)
    expect(status[Service.CODESPACE]).toBe(CodespaceStatus.STARTING)
  })
  test('AgentStatus', () => {
    const action: WorkbenchStoreAction = {
      type: 'STATUS',
      payload: {service: Service.AGENT, status: AgentStatus.GENERATING},
    }
    const {status} = workbenchStoreReducer(initialState, action)
    expect(status[Service.AGENT]).toBe(AgentStatus.GENERATING)
  })
  test('AcaStatus', () => {
    const action: WorkbenchStoreAction = {
      type: 'STATUS',
      payload: {service: Service.ACA, status: AcaStatus.NO_RESOURCES},
    }
    const {status} = workbenchStoreReducer(initialState, action)
    expect(status[Service.ACA]).toBe(AcaStatus.NO_RESOURCES)
  })
})

describe('errors', () => {
  test('add an error for a specific service', () => {
    const action: WorkbenchStoreAction = {
      type: 'ERROR',
      payload: {service: Service.VITE, type: ErrorType.SPARK_VITE_ERROR},
    }
    const {status, errors} = workbenchStoreReducer(initialState, action)
    expect(status[Service.VITE]).toBe(Status.ERROR)
    expect(errors.length).toBe(1)
    expect(errors[0]?.type).toBe(ErrorType.SPARK_VITE_ERROR)
    expect(errors[0]?.service).toBe(Service.VITE)
  })
  test('add multiple errors', () => {
    const action: WorkbenchStoreAction = {
      type: 'ERROR',
      payload: {service: Service.VITE, type: ErrorType.SPARK_VITE_ERROR},
    }
    const firstState = workbenchStoreReducer(initialState, action)
    expect(firstState.errors.length).toBe(1)
    const secondState = workbenchStoreReducer(firstState, {
      ...action,
      payload: {
        service: Service.AGENT,
        type: ErrorType.SPARK_RUNTIME_ERROR,
      },
    })
    expect(secondState.errors.length).toBe(2)
    expect(secondState.errors[1]?.type).toBe(ErrorType.SPARK_RUNTIME_ERROR)
    expect(secondState.errors[1]?.service).toBe(Service.AGENT)
  })
  test('clear all existing errors', () => {
    const action: WorkbenchStoreAction = {
      type: 'CLEAR_ERRORS',
    }
    const {errors} = workbenchStoreReducer(
      {
        ...initialState,
        errors: [{type: ErrorType.SPARK_VITE_ERROR, service: Service.VITE}],
      },
      action,
    )
    expect(errors.length).toBe(0)
  })
  test('clear existing errors for a specific service', () => {
    const action: WorkbenchStoreAction = {
      type: 'CLEAR_ERRORS',
      payload: Service.CODESPACE,
    }
    const {errors} = workbenchStoreReducer(
      {
        ...initialState,
        errors: [
          {type: ErrorType.SPARK_VITE_ERROR, service: Service.COPILOT},
          {type: ErrorType.SPARK_RUNTIME_ERROR, service: Service.CODESPACE},
        ],
      },
      action,
    )
    expect(errors.length).toBe(1)
    expect(errors[0]?.service).toBe(Service.COPILOT)
    expect(errors[0]?.type).toBe(ErrorType.SPARK_VITE_ERROR)
  })
})
