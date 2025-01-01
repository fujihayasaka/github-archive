import {announce} from '@github-ui/aria-live'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useNavigate} from '@github-ui/use-navigate'
import {type FileStatuses, WebCommitDialog, type WebCommitDialogState} from '@github-ui/web-commit-dialog'
import {FileStatusIcon} from '@github-ui/web-commit-dialog/FileStatusIcon'
import {Button, Checkbox, ConfirmationDialog, FormControl} from '@primer/react'
import {InlineMessage} from '@primer/react/experimental'
import {useCallback, useEffect, useRef, useState} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useWorkspaceEditorUIDispatch} from '../contexts/WorkspaceEditorUIContext'
import {useCommitChanges} from '../hooks/use-commit-changes'
import {useGenerateCommitMessage} from '../hooks/use-generate-commit-message'
import {FAILURE_VALUE, SUCCESS_VALUE} from '../telemetry/constants'
import type {TTelemetryPropertyBag} from '../telemetry/interfaces'
import {useAnalytics} from '../telemetry/use-analytics'
import {mapPatchToDiffLines} from '../utilities/diff-helpers'
import type {ChangedFile, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import styles from './CommitPanel.module.css'
import {Diff} from './Diff'

export interface CommitPanelProps {
  onClose: () => void
  fileStatuses: FileStatuses
  dialogState: WebCommitDialogState
  setDialogState: (state: WebCommitDialogState) => void
  commitButtonRef: React.RefObject<HTMLButtonElement>
}

const DEFAULT_COMMIT_MESSAGE = 'Updates from editor'

function getCommitDetails(
  message: string | undefined,
  generatedCommitMessage: {commitMessage: string; description?: string} | undefined | null,
  description: string | undefined,
  isLoading: boolean,
  copilotEnabled: boolean,
): {commitMessage: string; commitDescription: string} {
  const commitMessage =
    message ??
    generatedCommitMessage?.commitMessage ??
    ((!isLoading && copilotEnabled) || !copilotEnabled ? DEFAULT_COMMIT_MESSAGE : '')

  const commitDescription = description ?? generatedCommitMessage?.description ?? ''

  return {commitMessage, commitDescription}
}

export function CommitPanel({onClose, fileStatuses, dialogState, setDialogState, commitButtonRef}: CommitPanelProps) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {
    repo,
    webCommitInfo: {authorEmails, defaultEmail, defaultNewBranchName},
  } = payload
  const {pullRequest} = useCurrentPullRequest()
  const navigate = useNavigate()
  const {resetFiles, getChangedFiles} = useFilesContext()
  const [confirmationIsOpen, setConfirmationIsOpen] = useState(false)
  const buttonRef = useRef<HTMLButtonElement>(null)
  const {commitChanges} = useCommitChanges()
  const dispatch = useWorkspaceEditorUIDispatch()
  const [errorMessage, setErrorMessage] = useState<string>()
  const [selectedFiles, setSelectedFiles] = useState(() => new Set<string>(Object.keys(fileStatuses)))
  const [authorEmail, setAuthorEmail] = useState(authorEmails.length ? defaultEmail : undefined)

  const [message, setMessage] = useState<string>()
  const [description, setDescription] = useState<string>()
  const [isQuickPull, setIsQuickPull] = useState(!pullRequest.isOpen)
  const [prTargetBranch, setPRTargetBranch] = useState(defaultNewBranchName)
  const sendEvent = useAnalytics()

  const {generatedCommitMessage, isLoading} = useGenerateCommitMessage({
    changedFiles: getChangedFiles().filter(f => selectedFiles.has(f.path)),
  })

  const {commitMessage, commitDescription} = getCommitDetails(
    message,
    generatedCommitMessage,
    description,
    isLoading,
    payload.copilotAccessAllowed,
  )

  const saveHandler = async () => {
    // common commit telemetry data
    const commitTelemetryData: TTelemetryPropertyBag = {
      description_length: commitDescription?.length || 0,
      commited_files_count: selectedFiles.size,
    }

    const startTime = performance.now()

    try {
      setDialogState('saving')
      setErrorMessage(undefined)

      const result = await commitChanges({
        commitMessage,
        commitDescription,
        headBranch: isQuickPull ? prTargetBranch : pullRequest.headBranch,
        headSHA: pullRequest.headSHA,
        ownerLogin: repo.ownerLogin,
        pullRequestNumber: pullRequest.number,
        repoName: repo.name,
        selectedFiles,
        authorEmail,
        isQuickPull,
      })

      if (result?.compare_url) {
        navigate(result.compare_url)
        return
      }

      dispatch({
        type: 'SET_BANNER',
        banner: 'commit-success',
      })

      commitTelemetryData['result'] = SUCCESS_VALUE

      onClose()
    } catch (error) {
      commitTelemetryData['result'] = FAILURE_VALUE
      commitTelemetryData['result_message'] = `${error}`

      setDialogState('pending')

      if (error instanceof Error) {
        setErrorMessage(error.message)
      }
    } finally {
      sendEvent('editor.commit', {
        ...commitTelemetryData,
        time_elapsed_ms: performance.now() - startTime,
      })
    }
  }

  const onDialogClose = (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
    if (gesture === 'confirm') {
      const startTime = performance.now()
      // common reset telemetry data
      const resetData: TTelemetryPropertyBag = {
        description_length: commitDescription.length,
        changed_files_count: getChangedFiles().length,
      }

      try {
        resetFiles()
        resetData['result'] = SUCCESS_VALUE
      } catch (error) {
        resetData['result'] = FAILURE_VALUE
        resetData['result_message'] = `${error}`
      } finally {
        sendEvent('editor.reset', {
          ...resetData,
          time_elapsed_ms: performance.now() - startTime,
        })
      }
      onClose()
    } else {
      setConfirmationIsOpen(false)
    }
  }

  const preventSubmitReasons = [
    selectedFiles.size === 0 && 'Select files to commit',
    !commitMessage && 'Provide a commit message',
  ]
  const preventSubmit = preventSubmitReasons.some(Boolean)
  const preventSubmitMessage = preventSubmitReasons.filter(Boolean).join(', ').concat('.')

  return (
    <WebCommitDialog
      additionalFooterContent={
        <>
          <Button
            ref={buttonRef}
            onClick={() => setConfirmationIsOpen(!confirmationIsOpen)}
            variant="danger"
            className="mr-auto"
          >
            Reset all changes
          </Button>
          {confirmationIsOpen && (
            <ConfirmationDialog
              title="Reset all changes"
              onClose={onDialogClose}
              cancelButtonContent="Never mind"
              confirmButtonContent="Yes, reset"
              confirmButtonType="danger"
            >
              Are you sure you want to discard your changes?
            </ConfirmationDialog>
          )}
        </>
      }
      dialogProps={{position: 'right', height: 'auto'}}
      webCommitInfo={payload.webCommitInfo}
      onSave={saveHandler}
      helpUrl={payload.helpUrl}
      refName={payload.refInfo.name}
      dialogState={dialogState}
      setDialogState={setDialogState}
      placeholderMessage={isLoading ? 'Generating commit message...' : undefined}
      message={commitMessage}
      setMessage={setMessage}
      description={commitDescription}
      setDescription={setDescription}
      setAuthorEmail={setAuthorEmail}
      isQuickPull={isQuickPull}
      setIsQuickPull={setIsQuickPull}
      prTargetBranch={prTargetBranch}
      setPRTargetBranch={setPRTargetBranch}
      errorMessage={errorMessage}
      returnFocusRef={commitButtonRef}
      directCommitDisabled={!pullRequest.isOpen}
      preventSubmit={preventSubmit}
      preventSubmitMessage={preventSubmitMessage}
      diffList={
        <DiffForm changedFiles={getChangedFiles()} selectedFiles={selectedFiles} setSelectedFiles={setSelectedFiles} />
      }
    />
  )
}

function DiffForm({
  changedFiles,
  selectedFiles,
  setSelectedFiles,
}: {
  changedFiles: ChangedFile[]
  selectedFiles: Set<string>
  setSelectedFiles: (selectedFiles: Set<string>) => void
}) {
  const ariaLiveRef = useRef<HTMLDivElement>(null)
  const validationMessage = 'Select files to commit.'

  useEffect(() => {
    if (selectedFiles.size > 0) return
    if (ariaLiveRef.current) {
      const container = ariaLiveRef.current
      announce(validationMessage, {element: container})
    }
  }, [selectedFiles, ariaLiveRef])

  return (
    <div>
      <div role="status" aria-live="polite" ref={ariaLiveRef} className="sr-only" />
      <DiffList changedFiles={changedFiles} selectedFiles={selectedFiles} setSelectedFiles={setSelectedFiles} />
      {selectedFiles.size === 0 && (
        <InlineMessage variant="critical" className={styles.validationMessage}>
          {validationMessage}
        </InlineMessage>
      )}
    </div>
  )
}

function DiffList({
  changedFiles,
  selectedFiles,
  setSelectedFiles,
}: {
  changedFiles: ChangedFile[]
  selectedFiles: Set<string>
  setSelectedFiles: (selectedFiles: Set<string>) => void
}) {
  const checkboxHandler = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const path = event.target.value
      const newSelectedFiles = new Set(selectedFiles)
      if (newSelectedFiles.has(path)) {
        newSelectedFiles.delete(path)
      } else {
        newSelectedFiles.add(path)
      }
      setSelectedFiles(newSelectedFiles)
    },
    [selectedFiles, setSelectedFiles],
  )
  return changedFiles.map(changedFile => {
    const path = changedFile.patch.newFileName || changedFile.patch.oldFileName
    return path ? (
      <div className={styles.diffList} key={path}>
        <Diff
          headerPrefix={
            <FormControl>
              <Checkbox value={path} checked={selectedFiles.has(path)} onChange={checkboxHandler} aria-label={path} />
              <FormControl.Label className={styles.FormControl_Label}>
                <div className={styles.commitFileIcon}>
                  <FileStatusIcon status={changedFile.status} />
                </div>
              </FormControl.Label>
            </FormControl>
          }
          fileName={path}
          lines={mapPatchToDiffLines(changedFile.patch)}
          outdated={false}
          initiallyCollapsed
        />
      </div>
    ) : null
  })
}
