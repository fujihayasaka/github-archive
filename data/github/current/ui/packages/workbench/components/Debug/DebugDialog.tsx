import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {DatabaseIcon, DownloadIcon, TrashIcon, ZapIcon} from '@primer/octicons-react'
import {Button, Dialog, Heading, Stack, TreeView} from '@primer/react'
import {Banner} from '@primer/react/experimental'
import {useCallback} from 'react'

import {useCodespaceContext} from '../../contexts/CodespaceContext'
import {useDatabaseContext} from '../../contexts/DatabaseContext'
import {useFileSyncerContext} from '../../contexts/FileSyncerContext'
import {useIterationHistory} from '../../contexts/IterationHistoryContext'
import {usePublishingContext} from '../../contexts/PublishingContext'
import {useWorkbenchPreview} from '../../contexts/WorkbenchPreviewContext'
import type {WorkbenchRoutePayload} from '../../types/workbench-types'
import {DATABASE_DEFAULT, parseData} from '../../utilities/parse-data'
import {DebugBasicItem} from './DebugBasicItem'
import {DebugTreeItem} from './DebugTreeItem'

export interface DebugDialogProps {
  onClose: () => void
}

const LOG_FILES = {
  agent: ['/var/log/spark-server.log', '/var/log/spark-server.out.log', '/var/log/spark-server.err.log'],
  fileSyncer: ['/var/log/spark-file-syncer.out.log', '/var/log/spark-file-syncer.err.log'],
  publishing: ['/var/log/spark-publishing.log'],
  vite: ['/var/log/vite.out.log', '/var/log/vite.err.log'],
  proxy: ['/var/log/proxy.out.log', '/var/log/proxy.err.log'],
  designer: ['/var/log/spark-designer.out.log', '/var/log/spark-designer.err.log'],
} as const

type LogGroupKey = keyof typeof LOG_FILES

export const DebugDialog = ({onClose}: DebugDialogProps) => {
  const {codespaceData} = useCodespaceContext()
  const publishingData = usePublishingContext()
  const routePayload = useRoutePayload<WorkbenchRoutePayload>()
  const iterationHistory = useIterationHistory()
  const {getFileSyncerV2, fileSyncerStarted} = useFileSyncerContext()
  const previewContext = useWorkbenchPreview()
  const databaseContext = useDatabaseContext()

  const createFileDownloadName = useCallback(
    (originalName: string, timestamp: Date) => {
      // Format the date like YYYYMMDD-HHMMSS
      const pad = (num: number) => String(num).padStart(2, '0')
      const year = timestamp.getFullYear()
      const month = pad(timestamp.getMonth() + 1) // Months are zero-based
      const day = pad(timestamp.getDate())
      const hours = pad(timestamp.getHours())
      const minutes = pad(timestamp.getMinutes())
      const seconds = pad(timestamp.getSeconds())
      const dateString = `${year}${month}${day}-${hours}${minutes}${seconds}`

      const appName = routePayload.friendlyName ?? routePayload.workbench.runtimePermanentName

      // Split the original name to trim all preceding path segments
      const nameParts = originalName.split('/')
      const originalNameWithoutPath = nameParts[nameParts.length - 1]

      return `${dateString}_${appName}_${originalNameWithoutPath}.txt`
    },
    [routePayload.friendlyName, routePayload.workbench.runtimePermanentName],
  )

  const downloadFile = useCallback(
    async (path: string, timestamp: Date) => {
      const fileSyncer = getFileSyncerV2()
      if (!fileSyncer) {
        return
      }
      let content: string = ''
      try {
        // the file syncer reads files relative to the workspace root, so we need to correct the path
        const correctedPath = `../..${path}`
        content = await fileSyncer.readFileString(correctedPath)
      } catch (error: unknown) {
        content = `Error accessing file: ${String(error)}`
      }

      // Download the file
      const blob = new Blob([content], {type: 'text/plain'})
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = createFileDownloadName(path, timestamp)
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
    },
    [createFileDownloadName, getFileSyncerV2],
  )

  // Generic download helper for a group of log files
  const downloadLogGroup = async (logKeys: LogGroupKey[], timestamp: Date) => {
    // NOTE: a delay between downloads is necessary for the download to work properly in some browsers
    const smallDelay = async () => {
      await new Promise(resolve => setTimeout(resolve, 50))
    }

    for (const key of logKeys) {
      const files = LOG_FILES[key]
      for (const file of files) {
        await downloadFile(file, timestamp)
        await smallDelay()
      }
    }
  }

  const downloadAgentLogs = async (timestamp: Date) => {
    await downloadLogGroup(['agent'], timestamp)
  }

  const downloadFileSyncerLogs = async (timestamp: Date) => {
    await downloadLogGroup(['fileSyncer'], timestamp)
  }

  const downloadPublishingLogs = async (timestamp: Date) => {
    await downloadLogGroup(['publishing'], timestamp)
  }

  const downloadViteLogs = async (timestamp: Date) => {
    await downloadLogGroup(['vite'], timestamp)
  }

  const downloadProxyLogs = async (timestamp: Date) => {
    await downloadLogGroup(['proxy'], timestamp)
  }

  const downloadDesignerLogs = async (timestamp: Date) => {
    await downloadLogGroup(['designer'], timestamp)
  }

  const downloadAllLogs = async () => {
    const timestamp = new Date()
    for (const key of Object.keys(LOG_FILES) as LogGroupKey[]) {
      await downloadLogGroup([key], timestamp)
    }
  }

  const seedDatabase = async () => {
    await databaseContext.updateKeyInDatabase('seed_keyString', parseData(JSON.stringify(DATABASE_DEFAULT.keyString)))
    await databaseContext.updateKeyInDatabase(
      'seed_keySimpleObject',
      parseData(JSON.stringify(DATABASE_DEFAULT.keySimpleObject)),
    )
    await databaseContext.updateKeyInDatabase(
      'seed_keySimpleArray',
      parseData(JSON.stringify(DATABASE_DEFAULT.keySimpleArray)),
    )
    await databaseContext.updateKeyInDatabase(
      'seed_keyNestedObject',
      parseData(JSON.stringify(DATABASE_DEFAULT.keyNestedObject)),
    )
    await databaseContext.updateKeyInDatabase(
      'seed_keySimpleTableArray',
      parseData(JSON.stringify(DATABASE_DEFAULT.keySimpleTableArray)),
    )
    await databaseContext.updateKeyInDatabase(
      'seed_keyComplexTableArray',
      parseData(JSON.stringify(DATABASE_DEFAULT.keyComplexTableArray)),
    )
  }

  let id_counter = 0
  return (
    <Dialog title={'Debug Panel'} position="right" onClose={onClose}>
      <Stack direction="vertical" gap="normal">
        <Heading as="h1" variant="medium">
          Basic information
        </Heading>
        <Stack direction="vertical" gap="condensed">
          <DebugBasicItem label="Runtime Permanent Name" data={routePayload.workbench.runtimePermanentName} />
          <DebugBasicItem
            label="Codespace Friendly Name"
            data={codespaceData.codespaceInfo?.environment_data.friendlyName}
          />
          <DebugBasicItem label="Workbench GUID" data={routePayload.workbench.id} />
          <DebugBasicItem label="Billable Owner" data={routePayload.workbench.billableOwner.login} />
        </Stack>
        <Heading as="h1" variant="medium">
          Logs
        </Heading>
        <Stack direction="vertical" gap="condensed">
          {!fileSyncerStarted && (
            <Banner
              variant="info"
              title="Logs are not available"
              description={`Downloading the logs depends on the file syncer and is currently not available.`}
            />
          )}
          <Button
            variant="primary"
            leadingVisual={DownloadIcon}
            disabled={!fileSyncerStarted}
            onClick={downloadAllLogs}
          >
            Download All Logs
          </Button>
          <Stack direction="horizontal" gap="condensed" justify="center" wrap="wrap">
            <Button
              leadingVisual={DownloadIcon}
              disabled={!fileSyncerStarted}
              onClick={() => downloadAgentLogs(new Date())}
            >
              Agent
            </Button>
            <Button
              leadingVisual={DownloadIcon}
              disabled={!fileSyncerStarted}
              onClick={() => downloadFileSyncerLogs(new Date())}
            >
              File Syncer
            </Button>
            <Button
              leadingVisual={DownloadIcon}
              disabled={!fileSyncerStarted}
              onClick={() => downloadPublishingLogs(new Date())}
            >
              Publishing
            </Button>
            <Button
              leadingVisual={DownloadIcon}
              disabled={!fileSyncerStarted}
              onClick={() => downloadViteLogs(new Date())}
            >
              Vite
            </Button>
            <Button
              leadingVisual={DownloadIcon}
              disabled={!fileSyncerStarted}
              onClick={() => downloadProxyLogs(new Date())}
            >
              Proxy
            </Button>
            <Button
              leadingVisual={DownloadIcon}
              disabled={!fileSyncerStarted}
              onClick={() => downloadDesignerLogs(new Date())}
            >
              Designer
            </Button>
          </Stack>
        </Stack>
        <Heading as="h1" variant="medium">
          Some context data
        </Heading>
        <TreeView aria-label="Context information">
          <TreeView.Item id={`parent-${id_counter++}`}>
            <TreeView.LeadingVisual>
              <TreeView.DirectoryIcon />
            </TreeView.LeadingVisual>
            Codespace
            <TreeView.SubTree>
              <DebugTreeItem label="codespaceState" data={codespaceData.codespaceState} id={id_counter++} />
              <DebugTreeItem label="isRecoveryContainer" data={codespaceData.isRecoveryContainer} id={id_counter++} />
              <DebugTreeItem label="workspaceRoot" data={codespaceData.workspaceRoot} id={id_counter++} />
              <DebugTreeItem
                label="cloud_environment.guid"
                data={codespaceData.codespaceInfo?.cloud_environment.guid}
                id={id_counter++}
              />
              <DebugTreeItem
                label="codespaceInfo?.environment_data.connection.sessionPath"
                data={codespaceData.codespaceInfo?.environment_data.connection.sessionPath}
                id={id_counter++}
              />
              <DebugTreeItem
                label="codespaceInfo?.environment_data.friendlyName"
                data={codespaceData.codespaceInfo?.environment_data.friendlyName}
                id={id_counter++}
              />
            </TreeView.SubTree>
          </TreeView.Item>
          <TreeView.Item id={`parent-${id_counter++}`}>
            <TreeView.LeadingVisual>
              <TreeView.DirectoryIcon />
            </TreeView.LeadingVisual>
            Publishing
            <TreeView.SubTree>
              <DebugTreeItem label="publishingStatus" data={publishingData.publishingStatus} id={id_counter++} />
              <DebugTreeItem label="canCurrentlyPublish" data={publishingData.canCurrentlyPublish} id={id_counter++} />
              <DebugTreeItem label="publishedUrl" data={publishingData.publishedUrl} id={id_counter++} />
              <DebugTreeItem label="previewUrl" data={publishingData.previewUrl} id={id_counter++} />
              <DebugTreeItem label="isPublishUpToDate" data={publishingData.isPublishUpToDate} id={id_counter++} />
            </TreeView.SubTree>
          </TreeView.Item>
          <TreeView.Item id={`parent-${id_counter++}`}>
            <TreeView.LeadingVisual>
              <TreeView.DirectoryIcon />
            </TreeView.LeadingVisual>
            Preview
            <TreeView.SubTree>
              <DebugTreeItem label="state" data={previewContext.state} id={id_counter++} />
              <DebugTreeItem label="errorQueue" data={previewContext.errorQueue} id={id_counter++} />
              <DebugTreeItem label="runtimeErrors" data={previewContext.runtimeErrors} id={id_counter++} />
            </TreeView.SubTree>
          </TreeView.Item>
          <TreeView.Item id={`parent-${id_counter++}`}>
            <TreeView.LeadingVisual>
              <TreeView.DirectoryIcon />
            </TreeView.LeadingVisual>
            Route Payload
            <TreeView.SubTree>
              <DebugTreeItem label="friendlyName" data={routePayload.friendlyName} id={id_counter++} />
              <DebugTreeItem label="login" data={routePayload.login} id={id_counter++} />
              <DebugTreeItem label="workbench" data={routePayload.workbench} id={id_counter++} />
              <DebugTreeItem label="deploymentVisibility" data={routePayload.deploymentVisibility} id={id_counter++} />
              <DebugTreeItem label="deploy" data={routePayload.deploy} id={id_counter++} />
            </TreeView.SubTree>
          </TreeView.Item>
          <TreeView.Item id={`parent-${id_counter++}`}>
            <TreeView.LeadingVisual>
              <TreeView.DirectoryIcon />
            </TreeView.LeadingVisual>
            Iteration History
            <TreeView.SubTree>
              <DebugTreeItem
                label="isNavigatingHistory"
                data={iterationHistory.isNavigatingHistory}
                id={id_counter++}
              />
              <DebugTreeItem
                label="currentRefinementId"
                data={iterationHistory.currentRefinementId}
                id={id_counter++}
              />
              <DebugTreeItem
                label="previousRefinements"
                data={iterationHistory.previousRefinements}
                id={id_counter++}
              />
            </TreeView.SubTree>
          </TreeView.Item>
        </TreeView>
        <Heading as="h1" variant="medium">
          Database operations
        </Heading>
        <Stack direction="horizontal" gap="condensed">
          <Button leadingVisual={ZapIcon} onClick={seedDatabase}>
            Seed database
          </Button>
          <Button leadingVisual={DatabaseIcon} onClick={databaseContext.fetchAllData}>
            Re-fetch
          </Button>
          <Button variant="danger" leadingVisual={TrashIcon} onClick={databaseContext.resetDatabase}>
            Full reset
          </Button>
        </Stack>
      </Stack>
    </Dialog>
  )
}

// Also reexport the component as default for lazy-loading
export default DebugDialog
