import {RemoteProvider} from '@github/codespaces-lsp'
import type {Repository} from '@github-ui/current-repository'
import type {SshChannel} from '@microsoft/dev-tunnels-ssh'
import {useCallback, useEffect, useMemo, useRef, useState} from 'react'
import {useIdleTimer} from 'react-idle-timer'

import {AggregateError} from '../errors'
import {UNKNOWN_VALUE} from '../telemetry/constants'
import {useAnalytics, useCodespaceAnalytics, useUpdateCodespaceMetadata} from '../telemetry/use-analytics'
import {assertDefined} from '../utilities/asserts'
import {withRetries} from '../utilities/with-retries'
import type {
  CodespaceInfoBase,
  ConnectedCodespaceData,
  PermissionsStatus,
  PullRequestData,
  TCodespaceState,
} from '../utilities/workspace-editor-types'
import {createCodespaceWithRetries} from './use-codespaces/create-codespace-with-retries'
import {
  fetchCodespacePermissionsStatus,
  pollForCodespacePermissionsAccepted,
} from './use-codespaces/fetch-codespace-permissions-status'
import {refreshCodespaceInfoWithRetries} from './use-codespaces/refresh-codespace-info-with-retries'

/**
 * Hook to create a new Codespace instance and wait for it to be ready.
 */
export function useCodespaces(repo: Repository, pullRequest: PullRequestData): ConnectedCodespaceData {
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
  const sendCodespaceEvent = useCodespaceAnalytics()
  const updateCodespaceMetadata = useUpdateCodespaceMetadata()
  const sendEvent = useAnalytics()

  const cloudEnvUrl = `/${repo.ownerLogin}/${repo.name}/pull/${pullRequest.number}/workspace_editor/cloud_environment`

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
            recreateCodespace()
            return
          }

          // For some reason the type is coming through with spaces like "f o c u s" so we need to strip them
          const activity = e?.type.replace(' ', '') || 'unknown'
          await remoteProvider.notifyClientActivity(['hadron', [activity]])
        } catch (error) {
          // If no stream is available, that means all RPC calls will fail so we need to create a new cloudspace
          if (error instanceof Error && error.message.includes('No stream available')) {
            recreateCodespace()
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
      remoteProviderRef = new RemoteProvider(tunnelProperties, 2)
      setRemoteProvider(remoteProviderRef)
    }

    // Check the various codespace statuses and opens the availability channel in the background
    if (remoteProviderRef && state === 'ready') {
      openAvailabilityChannel(remoteProviderRef)
      checkIsRecoveryContainer(remoteProviderRef)
      checkPermissionsStatus()
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
   * The main effect of the hook - creates a new Codespace instance and
   * waits for it to get to the `Available` state.
   */
  const createCodespace = useCallback(
    async (forceNewCodespace: boolean) => {
      const startTime = performance.now()

      try {
        // send the telemetry just before a new Codespace instance is requested
        sendCodespaceEvent('codespace.requested', {
          request_id: UNKNOWN_VALUE,
          sku: UNKNOWN_VALUE,
          image: UNKNOWN_VALUE,
          location: UNKNOWN_VALUE,
          environment: UNKNOWN_VALUE,
        })

        updateCodespaceInfo('creating')

        // Clear any previous error message
        setCreationErrorMessage(undefined)

        // create a new Codespace instance
        const {data, isReconnect} = await createCodespaceWithRetries(cloudEnvUrl, forceNewCodespace, {
          onBeforeRetry(error, retries_left) {
            // report itermittent errors to telemetry
            sendCodespaceEvent('codespace.error', {
              message: `Failed to create Codespace: ${error.message}`,
              retries_left,
              is_fatal: false,
            })
          },
        })

        // If we are connecting to a new codespace, clear the existing data
        if (!isReconnect) {
          resetCodespaceData()
        }

        // Update Codespace state and info.
        // Note: it is important to update the Codespace info before the `codespace.created`
        //       telemetry event is sent, so the Codespace metadata is not lost.
        updateCodespaceInfo('starting', data)

        // send the telemetry event for the Codespace being created
        const {skuName: sku, location} = data.environment_data
        sendCodespaceEvent('codespace.created', {
          sku,
          location,
          environment: UNKNOWN_VALUE,
          elapsed_time_ms: performance.now() - startTime,
        })

        // wait until the Codespace is in the `Available` state
        const refreshedData = await refreshCodespaceInfoWithRetries(`${cloudEnvUrl}/${data.cloud_environment.guid}`, {
          onBeforeRetry(error, retries_left) {
            // report itermittent errors to telemetry
            sendCodespaceEvent('codespace.error', {
              message: `Failed to refresh Codespace info: ${error.message}`,
              retries_left,
              is_fatal: false,
            })
          },
        })

        // Update Codespace state and info.
        // Note: it is important to update the Codespace info before the `codespace.ready`
        //       telemetry event is sent, so the Codespace metadata is not lost.
        updateCodespaceInfo('ready', refreshedData)

        const {skuName: refreshedSku, location: refreshedLocation} = refreshedData.environment_data
        // send the telemetry event for the Codespace being ready
        sendCodespaceEvent('codespace.ready', {
          sku: refreshedSku,
          location: refreshedLocation,
          environment: UNKNOWN_VALUE,
          elapsed_time_ms: performance.now() - startTime,
          is_reconnect: isReconnect,
        })
      } catch (error) {
        /**
         * Handle the fatal Codespace creation error and update the Codespace state.
         */

        // get an error message to send to telemetry
        const errorMessage = error instanceof Error ? error.message : `Unknown error object: ${error}.`
        setCreationErrorMessage(errorMessage)

        // get the total number of requests that were retried during Codespace creation
        const attemptsMade = error instanceof AggregateError ? error.errors.length : NaN

        // send the telemetry event for the Codespace creation failure
        sendCodespaceEvent('codespace.error', {
          message: `Codespace creation failed: ${errorMessage}`,
          attempts_made: attemptsMade,
          elapsed_time_ms: performance.now() - startTime,
          is_fatal: true,
        })

        // finally set the Codespace state to `failed` and clear the Codespace info
        // Note: it is important to update the Codespace state after the `codespace.error`
        //       telemetry event is sent, so existing Codespace metadata is not lost.
        updateCodespaceInfo('failed')
      }
    },
    // `sendCodespaceEvent` function always changes so we cannot have it in the dependencies list
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [cloudEnvUrl],
  )

  const initialCreationRequestSet = useRef<boolean>(false)

  // Immediately create a new Codespace instance when the hook is called
  useEffect(() => {
    if (initialCreationRequestSet.current) {
      return
    }
    initialCreationRequestSet.current = true
    createCodespace(false)
  }, [createCodespace, codespaceState])

  const recreateCodespace = useCallback(() => {
    resetCodespaceData()
    createCodespace(true)
  }, [resetCodespaceData, createCodespace])

  const pollForPermissionsAccepted = useCallback(async () => {
    const permissionsStatusResponse = await pollForCodespacePermissionsAccepted(`${cloudEnvUrl}/permissions_check`)
    if (permissionsStatusResponse?.accepted) {
      setPermissionsStatus(permissionsStatusResponse)

      // Recreate the codespace with the accepted permissions
      recreateCodespace()
    }
  }, [cloudEnvUrl, recreateCodespace])

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
   * Checks if there are any permissions that need to be accepted by the user for the codespace.
   */
  const checkPermissionsStatus = async () => {
    try {
      const permissionsStatusResponse = await fetchCodespacePermissionsStatus(`${cloudEnvUrl}/permissions_check`)
      setPermissionsStatus(permissionsStatusResponse)
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
          availabilityChannelRef.current.onClosed(args => {
            sendEvent('channel.closed', {
              message: `Availability channel closed: ${args.errorMessage ?? 'Unknown error'}`,
            })

            setAvailabilityChannelStatus('disconnected')

            // Clear the channel so that we don't try to use it again
            availabilityChannelRef.current = undefined
          })

          setAvailabilityChannelStatus('connected')
          sendEvent('channel.opened')
        },
        {
          onBeforeRetry(error, retries_left) {
            setAvailabilityChannelStatus('connecting')

            // Make sure that the channel is cleared before retrying
            availabilityChannelRef.current = undefined

            // Report to telemetry
            sendEvent('channel.error', {
              message: `Failed to open availability channel: ${error.message}`,
              retries_left,
            })
          },
          retries: 3,
          retryDelayMs: 1000,
        },
      )
    },
    [sendEvent, setAvailabilityChannelStatus],
  )

  return {
    workspaceRoot,
    codespaceState,
    codespaceInfo,
    remoteProvider,
    creationErrorMessage,
    isRecoveryContainer,
    permissionsStatus,
    recreateCodespace,
    pollForPermissionsAccepted,
  }
}
