import {isFeatureEnabled} from '@github-ui/feature-flags'

import {
  AcaStatus,
  AgentStatus,
  CodespaceStatus,
  Service,
  Status,
  useWorkbenchStore,
} from '../contexts/WorkbenchStoreContext'
import {Region} from '../types/workbench-types'
import {EntitledService} from '../utilities/workbench-store-reducer'

export {Region} from '../types/workbench-types'

export const RegionState = {
  ENABLED: 'enabled',
  DISABLED: 'disabled',
  READ_ONLY: 'readOnly',
} as const
type RegionState = (typeof RegionState)[keyof typeof RegionState]

export function useRegionState(region: Region) {
  const {readOnly: storeReadOnly, status, entitlement} = useWorkbenchStore()

  if (!isFeatureEnabled('workbench_store_readonly')) {
    return RegionState.ENABLED
  }

  const isCodespacesDown = status[Service.CODESPACE] !== Status.CONNECTED

  const globalReadOnly = storeReadOnly || isCodespacesDown
  // Chat quota exceeded
  const premiumInteractionsQuotaExceeded =
    (entitlement[EntitledService.COPILOT].quotas.remaining.premiumInteractions ?? 0) <= 0
  // Codespaces quota exceeded
  const concurrentSparksAllowed = entitlement[EntitledService.CODESPACE_SESSIONS].allowed
  // Codespace compute hours quota exceeded
  const computeHoursQuotaExceeded =
    entitlement[EntitledService.CODESPACE_COMPUTE].quotas.remaining.computeHoursPercentage <= 0

  const entitlementsQuotaReadOnly =
    status.codespace === Status.IDLE ||
    premiumInteractionsQuotaExceeded ||
    !concurrentSparksAllowed ||
    computeHoursQuotaExceeded

  let regionState = undefined
  switch (region) {
    case Region.EDITOR: {
      const disabled =
        status.codespace === CodespaceStatus.STARTING ||
        status.codespace === CodespaceStatus.NO_GIT ||
        status.codespace === Status.ERROR
      const readOnly =
        globalReadOnly ||
        status.agent === AgentStatus.GENERATING ||
        status.fileSyncer === Status.DISCONNECTED ||
        entitlementsQuotaReadOnly
      regionState = getRegionState(disabled, readOnly)
      break
    }
    case Region.PREVIEW: {
      const disabled =
        status.codespace === CodespaceStatus.STARTING ||
        status.codespace === Status.ERROR ||
        status.fileSyncer === Status.DISCONNECTED ||
        status.vite === Status.DISCONNECTED
      regionState = getRegionState(disabled, globalReadOnly)
      break
    }
    case Region.TARGETED_EDITS: {
      const disabled =
        status.codespace === CodespaceStatus.STARTING ||
        status.codespace === Status.ERROR ||
        status.fileSyncer === Status.DISCONNECTED ||
        status.designer === Status.DISCONNECTED ||
        status.vite === Status.DISCONNECTED
      const readOnly = globalReadOnly || entitlementsQuotaReadOnly
      regionState = getRegionState(disabled, readOnly)
      break
    }
    case Region.DEPLOY_BUTTON: {
      const disabled = status.codespace !== Status.CONNECTED || status.aca === AcaStatus.NO_RESOURCES
      const readOnly = globalReadOnly || entitlementsQuotaReadOnly
      regionState = getRegionState(disabled, readOnly)
      break
    }
    case Region.THEME: {
      const readOnly =
        globalReadOnly ||
        status.designer === Status.DISCONNECTED ||
        status.fileSyncer === Status.DISCONNECTED ||
        entitlementsQuotaReadOnly
      regionState = getRegionState(false, readOnly)
      break
    }
    case Region.DATA: {
      const disabled = status.aca === AcaStatus.NO_RESOURCES
      regionState = getRegionState(disabled, globalReadOnly)
      break
    }
    case Region.AI: {
      const disabled = status.codespace === Status.ERROR || status.codespace === CodespaceStatus.STARTING
      const readOnly = globalReadOnly || status.fileSyncer === Status.DISCONNECTED || entitlementsQuotaReadOnly
      regionState = getRegionState(disabled, readOnly)
      break
    }
    case Region.ASSETS: {
      const disabled = status.codespace === Status.ERROR || status.codespace === CodespaceStatus.STARTING
      const readOnly = globalReadOnly || status.fileSyncer === Status.DISCONNECTED || entitlementsQuotaReadOnly
      regionState = getRegionState(disabled, readOnly)
      break
    }
    // TODO: don't have a case for this one in the spreadsheet, copied iterate panel for now
    case Region.HISTORY: {
      const readOnly =
        globalReadOnly ||
        status.agent === AgentStatus.GENERATING ||
        status.agent === Status.DISCONNECTED ||
        status.fileSyncer === Status.DISCONNECTED ||
        entitlementsQuotaReadOnly
      regionState = getRegionState(false, readOnly)
      break
    }
    case Region.ITERATE: {
      const readOnly =
        globalReadOnly ||
        status.agent === AgentStatus.GENERATING ||
        status.agent === Status.DISCONNECTED ||
        status.fileSyncer === Status.DISCONNECTED ||
        entitlementsQuotaReadOnly
      regionState = getRegionState(false, readOnly)
      break
    }
    case Region.LOGS: {
      const disabled = status.vite === Status.DISCONNECTED
      regionState = getRegionState(disabled, globalReadOnly)
      break
    }
    case Region.SETTINGS: {
      regionState = getRegionState(false, globalReadOnly)
      break
    }
    default: {
      regionState = getRegionState(false, globalReadOnly)
      break
    }
  }
  return regionState
}

function getRegionState(disabled: boolean, readOnly: boolean): RegionState {
  if (disabled) {
    return RegionState.DISABLED
  } else if (readOnly) {
    return RegionState.READ_ONLY
  }
  return RegionState.ENABLED
}
