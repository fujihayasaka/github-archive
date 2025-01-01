import {CopyToClipboardButton} from '@github-ui/copy-to-clipboard/Button'
import {DownloadIcon, SyncIcon, XCircleFillIcon} from '@primer/octicons-react'
import {Button, Dialog, IconButton, Spinner} from '@primer/react'
import {useCallback, useEffect, useMemo, useState} from 'react'

import type {ConnectedCodespaceData} from '../utilities/workspace-editor-types'

interface IDetailsDialogProps {
  detailsDialogVisibility: 'visible' | 'hidden'
  onDetailsClick: () => void
  codespaceData: ConnectedCodespaceData
}

const downloadCreationLog = (creationLog: string) => {
  const blob = new Blob([creationLog], {type: 'text/plain;charset=utf-8'})
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = 'creation.log'
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

export function DetailsDialog({detailsDialogVisibility, onDetailsClick, codespaceData}: IDetailsDialogProps) {
  const [creationLog, setCreationLog] = useState<string>('')
  const [creationLogStatus, setCreationLogStatus] = useState<'none' | 'fetching' | 'failed' | 'succeeded'>('none')

  const {isRecoveryContainer, creationErrorMessage, remoteProvider, recreateCodespace} = codespaceData

  const helpText = useMemo(() => {
    if (isRecoveryContainer) {
      return 'Your codespace failed to start. Refer to the creation log for more details:'
    }
    return 'Your codespace failed to create due to the following error:'
  }, [isRecoveryContainer])

  const fetchCreationLog = useCallback(async () => {
    if (!remoteProvider) {
      return
    }

    setCreationLog('')
    setCreationLogStatus('fetching')
    const channel = await remoteProvider.getCommandChannel()
    channel.onExitCode(exitCode => {
      if (exitCode.status !== 0) {
        setCreationLogStatus('failed')
      } else {
        setCreationLogStatus('succeeded')
      }
    })
    channel.onStandardOutput(data => {
      setCreationLog(prev => prev + data)
    })
    channel.onErrorOutput(data => {
      setCreationLog(prev => prev + data)
    })
    await channel.executeCommand(`cat /workspaces/.codespaces/.persistedshare/creation.log`)
  }, [remoteProvider])

  useEffect(() => {
    if (isRecoveryContainer) {
      fetchCreationLog()
    }
  }, [isRecoveryContainer, fetchCreationLog])

  const creationLogComponent = useMemo(() => {
    if (!isRecoveryContainer) {
      return (
        <pre className="text-mono">
          <span className="log-info d-flex ws-pre-wrap text-center">{creationErrorMessage ?? 'Unknown error'}</span>
        </pre>
      )
    }

    if (creationLogStatus === 'fetching') {
      return (
        <div className="d-flex flex-column flex-items-center gap-2">
          <Spinner />
          <span>Fetching creation log</span>
        </div>
      )
    }
    if (creationLogStatus === 'succeeded') {
      return (
        <pre className="text-mono">
          <span className="log-info">{creationLog}</span>
        </pre>
      )
    }

    return (
      <div className="d-flex flex-column flex-items-center gap-2">
        <XCircleFillIcon size={32} className="color-fg-danger" />
        <span>Failed to fetch creation log</span>
      </div>
    )
  }, [creationLogStatus, creationLog, creationErrorMessage, isRecoveryContainer])

  const handleRecreateCodespace = () => {
    onDetailsClick()
    setCreationLog('')
    setCreationLogStatus('none')
    recreateCodespace()
  }

  if (detailsDialogVisibility === 'hidden') {
    return <></>
  }

  return (
    <Dialog
      title={`Problem ${isRecoveryContainer ? 'starting' : 'creating'} codespace`}
      sx={{
        width: '960px',
        height: '640px',
      }}
      onClose={onDetailsClick}
      renderFooter={() => {
        return (
          <Dialog.Footer>
            <Button onClick={handleRecreateCodespace}>Create new codespace</Button>
            <Button onClick={onDetailsClick} variant="primary">
              Close
            </Button>
          </Dialog.Footer>
        )
      }}
      renderBody={() => {
        return (
          <div className="d-flex flex-column height-full gap-2 px-3 pt-2 pb-3">
            <div className="d-flex flex-items-center flex-justify-between">
              <span>{helpText}</span>
              <div className="d-flex height-5">
                {creationLogStatus === 'succeeded' && (
                  <>
                    <IconButton
                      aria-label="Download creation log"
                      onClick={() => downloadCreationLog(creationLog)}
                      icon={DownloadIcon}
                      variant="invisible"
                    />
                    <CopyToClipboardButton textToCopy={creationLog} ariaLabel={'Copy creation log'} />
                  </>
                )}
                {creationLogStatus === 'failed' && (
                  <IconButton aria-label="Retry" onClick={fetchCreationLog} icon={SyncIcon} variant="invisible" />
                )}
              </div>
            </div>
            <div
              className="d-flex flex-1 bgColor-inset rounded-md overflow-auto p-3"
              style={{
                justifyContent: creationLogStatus !== 'succeeded' ? 'center' : 'flex-start',
                alignItems: creationLogStatus !== 'succeeded' ? 'center' : 'flex-start',
              }}
            >
              {creationLogComponent}
            </div>
          </div>
        )
      }}
    />
  )
}
