import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {verifiedFetch} from '@github-ui/verified-fetch'
import type React from 'react'
import {createContext, useCallback, useContext, useEffect, useMemo, useState} from 'react'

import {DeploymentVisibility} from '../types/deployment-types'
import type {WorkbenchRoutePayload} from '../types/workbench-types'
import {CommandTask} from '../utilities/terminal-reducer'
import {useCodespaceContext} from './CodespaceContext'
import {useIterationHistory} from './IterationHistoryContext'
import {useTerminalContext} from './TerminalContext'
import {useWorkbenchContext} from './WorkbenchContext'

export interface PublishingContextProps {}

export type PublishingStatus =
  | 'unpublished'
  | 'publishingFirstTime'
  | 'publishedFirstTime'
  | 'published'
  | 'republishing'
  | 'republishFailed'

export interface PublishingContextData {
  publishingStatus: PublishingStatus // The state machine status. See external docs for reference.
  publishedUrl?: string // The URL for the published deployment
  isPublishUpToDate: boolean // Is the published spark on the same SHA as our most recent iteration?
  previewUrl: string // The URL for the read-only previwe
  canCurrentlyPublish: boolean // Is now a time that the publishing action can happen?
  visibility: DeploymentVisibility // The visibility of published sparks (private? all github?, etc)
  setVisibility: (newVisibility: DeploymentVisibility) => Promise<void> // Set the visibility of the deployment
  startDeploymentPipeline: () => Promise<void> // Start the publishing process
  unpublish: () => Promise<void> // Unpublish the deployment
  cancelPublishing: () => void // Cancel an active publishing process
}

export const PublishingContext = createContext<PublishingContextData | undefined>(undefined)

export const PublishingProvider: React.FC<PublishingContextProps & {children: React.ReactNode}> = ({children}) => {
  const {
    codespaceData: {codespaceState},
  } = useCodespaceContext()
  const terminalContext = useTerminalContext()
  const {
    executeCommand,
    stopCommand,
    state: {history},
  } = terminalContext
  const deployCommand = history[CommandTask.Deploy]
  const {friendlyName, isFetching} = useWorkbenchContext()
  const {deploymentVisibility, deploy, workbench, previewDeploy} = useRoutePayload<WorkbenchRoutePayload>()
  const {previousRefinements} = useIterationHistory()
  const latestIterationSha = previousRefinements.at(-1)?.sha
  const use_deploy_script_from_sdk = useFeatureFlag('spark_use_deploy_script_from_sdk')

  const [publishingStatus, setPublishingStatus] = useState<PublishingStatus>('unpublished')
  const [publishedUrl, setPublishedUrl] = useState<string | undefined>(undefined)
  const [visibility, setRawVisibility] = useState<DeploymentVisibility>(
    deploymentVisibility || DeploymentVisibility.OnlyOwner,
  )

  const deployName = deploy ? `${friendlyName}--${deploy.deployLogin}.${deploy.domainBase}` : ''
  const previewUrl = previewDeploy
    ? `https://${previewDeploy.displayName}--${friendlyName}--${previewDeploy.deployLogin}.${previewDeploy.domainBase}`
    : ''
  const statusFromPayload = deploy ? 'success' : 'failure'

  useEffect(() => {
    // Determine if the payload contains the deploy object,
    // which would indicate that there was a previous deployment.
    // If so, set the publishing status to published.
    if (deployName.length > 0) {
      setPublishingStatus('published')
      setPublishedUrl(`https://${deployName}`)
    }
  }, [deployName, friendlyName])

  const startDeploymentPipeline = useCallback(async () => {
    try {
      setPublishingStatus(currentStatus => (currentStatus === 'unpublished' ? 'publishingFirstTime' : 'republishing'))
      const command = use_deploy_script_from_sdk
        ? `/usr/local/bin/deploy.sh | tee -a /var/log/spark-publishing.log`
        : `./deploy.sh | tee -a /var/log/spark-publishing.log`
      await executeCommand(command, CommandTask.Deploy)
    } catch {
      setPublishingStatus(currentStatus =>
        currentStatus === 'publishingFirstTime' ? 'unpublished' : 'republishFailed',
      )
    }
  }, [executeCommand, use_deploy_script_from_sdk])

  const unpublish = useCallback(async () => {
    // NO-OP right now
    // TODO:
    // 1. Create the unpublish API in dotcom
    // 2. use verifiedFetch to call the API
    // 3. Update the publishingStatus to unpublished
    // 4. Update the publishedUrl to undefined
  }, [])

  const cancelPublishing = useCallback(() => {
    stopCommand(deployCommand)
  }, [stopCommand, deployCommand])

  const {output, loading, startTime, endTime, stopped: isCommandStopped} = deployCommand

  const setVisibility = useCallback(
    async (newVisibility: DeploymentVisibility) => {
      // Send update...
      const response = await verifiedFetch(`/copilot/spark/runtime/deployment/${workbench.id}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          visibility: newVisibility,
        }),
      })

      if (response.ok) {
        setRawVisibility(newVisibility)
      }
    },
    [workbench.id, setRawVisibility],
  )

  // Only try to parse the command output and status if we're in the process of publishing.
  useEffect(() => {
    if (publishingStatus === 'publishingFirstTime' || publishingStatus === 'republishing') {
      // The best way we've determined if the command is still running is to check if the start time is set and the end time is not.
      const isCommandExecuting = !!(startTime && !endTime) || loading

      const isBuildComplete = output.includes(`[--Build: Complete--]`)
      const isDeployComplete = output.includes(`[--Deployment: Complete--]`)

      const urlMatches = output.match(/https:\/\/.*\.github\.app/)
      const urlFromCommands = !isCommandExecuting && urlMatches ? urlMatches[0] : ''

      const buildStatusFromCommands =
        !isCommandExecuting && !isBuildComplete ? 'failure' : isBuildComplete ? 'success' : 'pending'
      const deployStatusFromCommands = isCommandExecuting ? 'pending' : isDeployComplete ? 'success' : 'failure'

      const deployUrl = deployName !== '' ? `https://${deployName}` : urlFromCommands

      const buildStatus = startTime ? buildStatusFromCommands : statusFromPayload
      const deployStatus = startTime ? deployStatusFromCommands : statusFromPayload

      // Once the command has finished, we'll try to understand what to transition the state to.
      if (!isCommandExecuting || isCommandStopped) {
        if (deployStatus === 'success' && buildStatus === 'success') {
          setPublishingStatus(publishingStatus === 'republishing' ? 'published' : 'publishedFirstTime')
          setPublishedUrl(deployUrl)
        } else {
          setPublishingStatus(publishingStatus === 'republishing' ? 'republishFailed' : 'unpublished')
        }
      }
    }
  }, [publishingStatus, startTime, endTime, loading, output, deployName, statusFromPayload, isCommandStopped])

  useEffect(() => {
    // This timer is used to transition from 'publishedFirstTime' to 'published' after 3 seconds.
    // The `publishedFirstTime` status is used to show a special message to the user,
    // but it needs to transition to the normal modal status to present the other options.
    let timer: ReturnType<typeof setTimeout>
    if (publishingStatus === 'publishedFirstTime') {
      timer = setTimeout(() => {
        setPublishingStatus('published')
      }, 3000)
    }
    return () => clearTimeout(timer)
  }, [publishingStatus])

  const canCurrentlyPublish = !loading && !isFetching && codespaceState === 'ready'

  // TODO: This is tempoary to remove the Outdated logo until I can figure out the logic
  const isPublishUpToDate = latestIterationSha === deploy?.revision || true

  const contextValue = useMemo(
    () => ({
      publishingStatus,
      publishedUrl,
      canCurrentlyPublish,
      startDeploymentPipeline,
      visibility,
      setVisibility,
      unpublish,
      cancelPublishing,
      previewUrl,
      isPublishUpToDate,
    }),
    [
      publishingStatus,
      publishedUrl,
      canCurrentlyPublish,
      startDeploymentPipeline,
      visibility,
      setVisibility,
      unpublish,
      cancelPublishing,
      previewUrl,
      isPublishUpToDate,
    ],
  )

  return <PublishingContext.Provider value={contextValue}>{children}</PublishingContext.Provider>
}

export const usePublishingContext = () => {
  const context = useContext(PublishingContext)
  if (!context) {
    throw new Error('usePublishing must be used within a PublishingProvider')
  }
  return context
}
