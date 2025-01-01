import {mockClientEnv} from '@github-ui/client-env/mock'
import {renderHook} from '@testing-library/react'

import {type WorkbenchStoreProps, WorkbenchStoreWrapper} from '../../__tests__/WorkbenchStoreWrapper'
import {AcaStatus, CodespaceStatus, Service, Status} from '../../utilities/workbench-store-reducer'
import {Region, RegionState, useRegionState} from '../use-region-state'

function renderUseRegionState(region: Region, patchState: WorkbenchStoreProps = {}) {
  return renderHook(() => useRegionState(region), {wrapper: WorkbenchStoreWrapper(patchState)})
}

it('Always returns ENABLED unless FF enabled', () => {
  const disabledCodespacePatch = {
    status: {
      codespace: CodespaceStatus.STARTING,
    },
  }
  const {
    result: {current: stateWithoutFF},
  } = renderUseRegionState(Region.EDITOR, disabledCodespacePatch)

  expect(stateWithoutFF).toBe(RegionState.ENABLED)
  mockClientEnv({
    featureFlags: ['workbench_store_readonly'],
  })

  const {
    result: {current: stateWithFF},
  } = renderUseRegionState(Region.EDITOR, disabledCodespacePatch)
  expect(stateWithFF).toBe(RegionState.DISABLED)
})

describe('with FF enabled', () => {
  beforeEach(() => {
    mockClientEnv({
      featureFlags: ['workbench_store_readonly'],
    })
  })

  it('returns READ_ONLY if globalReadOnly is set', () => {
    const enabledPatch = {
      status: {
        fileSyncer: Status.CONNECTED,
        vite: Status.CONNECTED,
        codespace: CodespaceStatus.CONNECTED, // codespace has to be connected for write mode
      },
    }
    const globalReadOnlyPatch = {
      readOnly: true,
    }
    const {
      result: {current: stateWithoutReadOnly},
    } = renderUseRegionState(Region.PREVIEW, enabledPatch)

    expect(stateWithoutReadOnly).toBe(RegionState.ENABLED)

    const {
      result: {current: stateWithReadOnly},
    } = renderUseRegionState(Region.PREVIEW, {...globalReadOnlyPatch, ...enabledPatch})
    expect(stateWithReadOnly).toBe(RegionState.READ_ONLY)
  })

  it('returns READ_ONLY if codespaces is not CONNECTED', () => {
    const enabledPatch = {
      status: {
        agent: Status.CONNECTED,
        fileSyncer: Status.CONNECTED,
        vite: Status.CONNECTED,
        designer: Status.CONNECTED,
        aca: AcaStatus.RESOURCES_CREATED,
        copilot: Status.CONNECTED,
        codespace: CodespaceStatus.STARTING, // codespace has to be connected for write mode
      },
    }
    const {
      result: {current: stateWithStarting},
    } = renderUseRegionState(Region.THEME, enabledPatch)
    expect(stateWithStarting).toBe(RegionState.READ_ONLY)

    const {
      result: {current: stateWithNoGit},
    } = renderUseRegionState(Region.PREVIEW, {
      status: {
        ...enabledPatch.status,
        [Service.CODESPACE]: CodespaceStatus.NO_GIT, // codespace has to be connected for write mode
      },
    })
    expect(stateWithNoGit).toBe(RegionState.READ_ONLY)

    const {
      result: {current: stateWithNoNodeModules},
    } = renderUseRegionState(Region.EDITOR, {
      status: {
        ...enabledPatch.status,
        [Service.CODESPACE]: CodespaceStatus.NO_NODE_MODULES, // codespace has to be connected for write mode
      },
    })
    expect(stateWithNoNodeModules).toBe(RegionState.READ_ONLY)
  })
})
