import {RemoteProvider} from '@github/codespaces-lsp'
import type {Repository} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {CodespaceNotInTargetStateError} from '@github-ui/workspace-editor/errors'
import {createCodespaceWithRetries} from '@github-ui/workspace-editor/lsp/use-codespaces/create-codespace-with-retries'
import {UNKNOWN_VALUE} from '@github-ui/workspace-editor/telemetry/constants'
import {useUpdateCodespaceMetadata} from '@github-ui/workspace-editor/telemetry/use-analytics'
import {assertDefined} from '@github-ui/workspace-editor/utilities/asserts'
import {withRetries} from '@github-ui/workspace-editor/utilities/with-retries'
import {
  type CodespaceInfoBase,
  CodespaceStateInfo,
  type ConnectedCodespaceData,
  type PermissionsStatus,
  type TCodespaceState,
} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import type {SshChannel} from '@microsoft/dev-tunnels-ssh'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useIdleTimer} from 'react-idle-timer'

import {useAnalytics} from '../telemetry/use-analytics'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {pollCodespaceUntilTargetState} from './use-codespaces/poll-codespace-until-target-state'
import {startCodespaceWithRetries} from './use-codespaces/start-codespace-with-retries'

/**
 * Hook to create a new Codespace instance and wait for it to be ready.
 */
export function useCodespaces(repo: Repository): ConnectedCodespaceData {
  const workspaceRoot = useMemo(() => `/var/lib/docker/codespacemount/workspace/${repo.name}`, [repo.name])
  const [codespaceInfo, setCodespaceInfo] = useState<CodespaceInfoBase | null>(null)
  const [codespaceState, setCodespaceState] = useState<TCodespaceState>('none')
  const [creationErrorMessage, setCreationErrorMessage] = useState<string | undefined>(undefined)
  const [remoteProvider, setRemoteProvider] = useState<RemoteProvider | undefined>(undefined)
  const [isRecoveryContainer, setIsRecoveryContainer] = useState<boolean>(false)
  const [permissionsStatus, setPermissionsStatus] = useState<PermissionsStatus | undefined>(undefined)
  const [availabilityChannelStatus, setAvailabilityChannelStatus] = useState<
    'connecting' | 'connected' | 'disconnected'
  >('connecting')
  const availabilityChannelRef = useRef<SshChannel | undefined>(undefined)
  const updateCodespaceMetadata = useUpdateCodespaceMetadata()
  const sendEvent = useAnalytics()

  const payload = useRoutePayload<WorkbenchRoutePayload>()
  const cloudEnvUrl = `/${repo.ownerLogin}/${repo.name}/copilot/workbench/cloud_environment`

  const resetCodespaceData = useCallback(() => {
    setIsRecoveryContainer(false)
    setRemoteProvider(undefined)
    updateCodespaceMetadata(null)
    setCodespaceInfo(null)
    setPermissionsStatus(undefined)
    availabilityChannelRef.current = undefined
  }, [updateCodespaceMetadata])

  // Listen for user activity to send activity signals to the cloudspace
  useIdleTimer({
    onAction: async e => {
      if (remoteProvider) {
        try {
          if (availabilityChannelStatus === 'disconnected') {
            retryGetOrCreateCodespace()
            return
          }

          // For some reason the type is coming through with spaces like "f o c u s" so we need to strip them
          const activity = e?.type.replace(' ', '') || 'unknown'
          await remoteProvider.notifyClientActivity(['workbench', [activity]])
        } catch (error) {
          // If no stream is available, that means all RPC calls will fail so we need to create a new cloudspace
          if (error instanceof Error && error.message.includes('No stream available')) {
            retryGetOrCreateCodespace()
          }
        }
      }
    },
    throttle: 5000,
  })

  /**
   * A helper function to update Codespace `info`, current `state`, update the telemetry `metadata`, and
   * set the `remote provider` instance. The `creating` and `failed` states do not have any associated
   * Codespace info data as all the other states do.
   */
  function updateCodespaceInfo(state: 'creating'): void
  function updateCodespaceInfo(state: 'failed'): void
  function updateCodespaceInfo(state: 'starting', data: CodespaceInfoBase): void
  function updateCodespaceInfo(state: 'ready', data: CodespaceInfoBase): void
  function updateCodespaceInfo(state: 'creating' | 'failed' | 'starting' | 'ready', data?: CodespaceInfoBase): void {
    // update the Codespace state first
    setCodespaceState(state)

    // the `creating` state does not have any data, so nothing to
    // update besides the Codespace state itself
    if (state === 'creating') {
      return
    }

    // the `failed` state must reset the Codespace info and metadata
    if (state === 'failed') {
      resetCodespaceData()
      return
    }

    // all other states must have the Codespace info set
    assertDefined(data, `Codespace info must be set for the ${state} state.`)

    const {environment_data, cloud_environment} = data
    const {connection} = environment_data
    const {tunnelProperties} = connection

    // create remote provider when tunnel properties are available
    let remoteProviderRef = remoteProvider
    if (tunnelProperties && !remoteProviderRef) {
      remoteProviderRef = new RemoteProvider(tunnelProperties, 3)
      setRemoteProvider(remoteProviderRef)
    }

    // Check the various codespace statuses and opens the availability channel in the background
    if (remoteProviderRef && state === 'ready') {
      openAvailabilityChannel(remoteProviderRef)
      checkIsRecoveryContainer(remoteProviderRef)
      // checkPermissionsStatus()
    }

    // update the Codespace context metadata
    updateCodespaceMetadata({
      codespace_id: cloud_environment.guid,
      codespace_session_id: UNKNOWN_VALUE,
      connection_id: tunnelProperties?.tunnelId,
      cluster_id: tunnelProperties?.clusterId,
    })
    setCodespaceInfo(data)
  }

  /**
   * The main effect of the hook - creates a new Codespace instance or connect to an existing one and
   * waits for it to get to the `Available` state.
   */
  const getOrCreateCodespace = useCallback(
    async () => {
      // if (process.env.NODE_ENV === 'development') {
      //   updateCodespaceInfo('ready', productionCodespace.codespaceInfo)
      //   return
      // }
      try {
        const startTime = performance.now()

        // send the telemetry just before a new Codespace instance is requested
        sendEvent('codespace.requested', {
          ...createTelemetryProps(),
        })

        updateCodespaceInfo('creating')

        // Clear any previous error message
        setCreationErrorMessage(undefined)

        // Finds or creates a codespace
        const codespaceInfoExtended = await createCodespaceWithRetries(
          `${cloudEnvUrl}?spark_id=${payload.workbench.id}`,
          false,
          {
            onBeforeRetry(_error, _retries_left) {
              // report itermittent errors to telemetry
              sendEvent('codespace.error', {
                message: `Failed to create Codespace: ${_error.message}`,
                _retries_left,
                is_fatal: false,
                ...createTelemetryProps(),
              })
            },
          },
        )

        // Reset the current Codespace data, even if we are resuming an existing Codespace,
        // certain properties such as the tunnelDetails will be new for each Codespace session.
        resetCodespaceData()

        let data = codespaceInfoExtended.data
        const cloudEnvironmentId = data.cloud_environment.guid

        // update info and send telemetry event
        updateCodespaceInfo('starting', data)
        sendEvent('codespace.created', {
          ...createTelemetryProps(data),
          elapsed_time_ms: performance.now() - startTime,
        })

        if (data.environment_data?.state === CodespaceStateInfo.ShuttingDown) {
          // wait until the Codespace is in the `Shutdown` state
          data = await pollCodespaceUntilTargetState(
            `${cloudEnvUrl}/${cloudEnvironmentId}`,
            CodespaceStateInfo.Shutdown,
            {
              onBeforeRetry(_error, _retries_left) {
                if (!(_error instanceof CodespaceNotInTargetStateError)) {
                  // Telemetry only for real errors, not while waiting for state change
                  sendEvent('codespace.error', {
                    message: `Failed while shutting down codespace: ${_error.message}`,
                    _retries_left,
                    is_fatal: false,
                    ...createTelemetryProps(data),
                  })
                }
              },
            },
          )

          updateCodespaceInfo('starting', data)
        }

        if (data.environment_data?.state === CodespaceStateInfo.Shutdown) {
          // If the codespace is in the `Shutdown` state, we need to start it
          data = await startCodespaceWithRetries(`${cloudEnvUrl}/${cloudEnvironmentId}`, {
            onBeforeRetry(_error, _retries_left) {
              sendEvent('codespace.error', {
                message: `Failed to start the codespace: ${_error.message}`,
                _retries_left,
                is_fatal: false,
                ...createTelemetryProps(data),
              })
            },
          })

          updateCodespaceInfo('starting', data)
        }

        // wait until the Codespace is in the `Available` state
        data = await pollCodespaceUntilTargetState(
          `${cloudEnvUrl}/${cloudEnvironmentId}`,
          CodespaceStateInfo.Available,
          {
            onBeforeRetry(_error, _retries_left) {
              if (!(_error instanceof CodespaceNotInTargetStateError)) {
                // Telemetry only for real errors, not while waiting for state change
                sendEvent('codespace.error', {
                  message: `Failed while waiting for the codespace to become Available: ${_error.message}`,
                  _retries_left,
                  is_fatal: false,
                  ...createTelemetryProps(data),
                })
              }
            },
          },
        )

        // update info and send telemetry event
        updateCodespaceInfo('ready', data)
        sendEvent('codespace.ready', {
          elapsed_time_ms: performance.now() - startTime,
          ...createTelemetryProps(data),
        })
      } catch (error) {
        /**
         * Handle the fatal Codespace creation error and update the Codespace state.
         */

        // get an error message to send to telemetry
        const errorMessage = error instanceof Error ? error.message : `Unknown error object: ${error}.`
        setCreationErrorMessage(errorMessage)

        // get the total number of requests that were retried during Codespace creation

        // finally set the Codespace state to `failed` and clear the Codespace info
        // Note: it is important to update the Codespace state after the `codespace.error`
        //       telemetry event is sent, so existing Codespace metadata is not lost.
        updateCodespaceInfo('failed')
      }
    },
    // `sendCodespaceEvent` function always changes so we cannot have it in the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [cloudEnvUrl],
  )

  function createTelemetryProps(data?: CodespaceInfoBase) {
    return {
      codespace_id: data?.cloud_environment?.guid ?? UNKNOWN_VALUE,
      sku: data?.environment_data?.skuName ?? UNKNOWN_VALUE,
      location: data?.environment_data?.location ?? UNKNOWN_VALUE,
      connection_id: data?.environment_data?.connection?.tunnelProperties?.tunnelId ?? UNKNOWN_VALUE,
      cluster_id: data?.environment_data?.connection?.tunnelProperties?.clusterId ?? UNKNOWN_VALUE,
      state: data?.environment_data?.state ?? UNKNOWN_VALUE,
    }
  }

  const initialCreationRequestSet = useRef<boolean>(false)

  // Immediately create a new Codespace instance when the hook is called
  useEffect(() => {
    if (initialCreationRequestSet.current) {
      return
    }
    initialCreationRequestSet.current = true
    getOrCreateCodespace()
  }, [getOrCreateCodespace, codespaceState])

  const retryGetOrCreateCodespace = useCallback(async () => {
    resetCodespaceData()
    await getOrCreateCodespace()
  }, [resetCodespaceData, getOrCreateCodespace])

  /**
   * Checks if the Codespace is in a recovery container.
   */
  const checkIsRecoveryContainer = async (remoteProviderRef: RemoteProvider) => {
    try {
      const isRecoveryContainerResponse = await remoteProviderRef.isRecoveryContainer()
      setIsRecoveryContainer(isRecoveryContainerResponse)
    } catch {
      // Do nothing
    }
  }

  /**
   * Keeps an SSH channel to the codespace open to ensure that it is still available.
   * When the channel closes, we will check if the codespace is still exists and if not,
   * will create a new one to replace it.
   */
  const openAvailabilityChannel = useCallback(
    (remoteProviderRef: RemoteProvider) => {
      withRetries(
        async () => {
          // If we already have a channel open, do nothing
          if (availabilityChannelRef.current) {
            return
          }

          availabilityChannelRef.current = await remoteProviderRef.getTerminalChannel({})
          availabilityChannelRef.current.onClosed(_args => {
            setAvailabilityChannelStatus('disconnected')

            // Clear the channel so that we don't try to use it again
            availabilityChannelRef.current = undefined
          })

          setAvailabilityChannelStatus('connected')
        },
        {
          onBeforeRetry(_error, _retries_left) {
            setAvailabilityChannelStatus('connecting')

            // Make sure that the channel is cleared before retrying
            availabilityChannelRef.current = undefined
          },
          retries: 3,
          retryDelayMs: 1000,
        },
      )
    },
    [setAvailabilityChannelStatus],
  )

  const pollForPermissionsAccepted = useCallback(() => {}, [])
  // if (process.env.NODE_ENV === 'development') {
  //   return productionCodespace
  // }
  return {
    workspaceRoot,
    codespaceState,
    codespaceInfo,
    remoteProvider,
    creationErrorMessage,
    isRecoveryContainer,
    permissionsStatus,
    recreateCodespace: retryGetOrCreateCodespace,
    pollForPermissionsAccepted,
  }
}
