import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {DiffHunkReference, TerminalLogReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {PencilIcon, PlayIcon, PlusIcon, SquareFillIcon, SyncIcon, ToolsIcon, TrashIcon} from '@primer/octicons-react'
import {IconButton, Spinner} from '@primer/react'
import {formatPatch} from 'diff'
import {useCallback, useMemo, useRef} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useFixABuildContext} from '../contexts/FixABuildContext'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useAnalytics} from '../telemetry/use-analytics'
import {commandTaskToString} from '../utilities/command-task-to-string'
import type {CommandResult} from '../utilities/terminal-reducer'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'

const FIX_BUILD_PROMPT =
  'Look at the attached terminal log output, as well as the attached changes to files in this repository. Then, make a plan and analyze failure in the log by looking at related files either in this repo, or attached as references to explain the error. What is the error and how can it be fixed?'

interface TerminalCommandActionsProps {
  command: CommandResult
  commandExecuted: boolean
  commandForTask?: string
  commandInputRef: React.RefObject<HTMLInputElement>
  editCommandRef: React.RefObject<HTMLButtonElement>
  setEditingCommand: (editingCommand: boolean) => void
}

const TerminalCommandActions: React.FC<TerminalCommandActionsProps> = ({
  command,
  commandForTask,
  commandExecuted,
  commandInputRef,
  editCommandRef,
  setEditingCommand,
}) => {
  const {executeCommand, stopCommand, dispatch: terminalDispatch} = useTerminalContext()
  const {task, exitCode, stopped, output} = command
  const fixBuildRef = useRef<HTMLButtonElement>(null)
  const sendEvent = useAnalytics()
  const fixABuildFunctionCallingEnabled = useFeatureFlag('workspace_editor_fix_a_build_function_calling')
  const dotcomClientSideSkillsEnabled = useFeatureFlag('dotcom_chat_client_side_skills')
  const taskString = commandTaskToString(task)
  const {fixABuild, loading: fixABuildLoading} = useFixABuildContext()
  const {copilotAccessAllowed, repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const showFixABuildButton = !!exitCode && !!output && copilotAccessAllowed
  const {pullRequest} = useCurrentPullRequest()
  const {getChangedFiles} = useFilesContext()

  const manager = useChatManager()
  const editorDispatch = useWorkspaceEditorUIDispatch()
  const state = useWorkspaceEditorUIState()

  const clearTask = useCallback(() => {
    terminalDispatch({type: 'CLEAR_TASK', task})
  }, [terminalDispatch, task])

  const handleEditCommand = useCallback(() => {
    setTimeout(() => commandInputRef?.current?.focus(), 0)
    setEditingCommand(true)
  }, [commandInputRef, setEditingCommand])

  const references = useMemo(() => {
    if (!showFixABuildButton) return
    const logRef: TerminalLogReference = {
      type: 'workspace-terminal-log',
      output,
      pullRequestID: pullRequest.id,
      repoID: repo.id,
      repoOwner: repo.ownerLogin,
      repoName: repo.name,
    }

    const changedFiles = getChangedFiles()
    const changedFilesRefs: DiffHunkReference[] = changedFiles.map(file => ({
      type: 'diff-hunk',
      changeReference: '',
      fileName: file.path,
      headerContext: '',
      diff: formatPatch(file.patch),
    }))

    return {logRef, changedFilesRefs}
  }, [getChangedFiles, output, pullRequest.id, repo, showFixABuildButton])

  const handleFixABuildClick = () => {
    if (fixABuildFunctionCallingEnabled && dotcomClientSideSkillsEnabled) {
      sendEvent('terminal.fix_build', {
        task: taskString,
        filesChangedCount: getChangedFiles().length,
      })
      return fixABuild()
    } else {
      return attachOutputToChat()
    }
  }

  const attachOutputToChat = () => {
    if (!showFixABuildButton || !references) return
    const {logRef, changedFilesRefs} = references
    if (state.rightPanel !== RightPanelType.Chat) {
      editorDispatch({
        type: 'TOGGLE_RIGHT_PANEL',
        rightPanel: RightPanelType.Chat,
        rightPanelButton: fixBuildRef.current ?? undefined,
      })
    }

    const referencesToSend = [logRef, ...(changedFilesRefs || [])]
    manager.sendChatMessage({thread: null, content: FIX_BUILD_PROMPT, references: referencesToSend})
    sendEvent('terminal.fix_build', {
      task: taskString,
      referenceCount: referencesToSend.length,
      referenceCharacterCount:
        logRef.output.length + (changedFilesRefs?.reduce((acc, ref) => acc + ref.diff.length, 0) || 0),
    })
  }

  return (
    <div className="d-flex">
      {!stopped && commandExecuted && exitCode === null ? (
        <IconButton
          icon={SquareFillIcon}
          onClick={() => stopCommand(command)}
          variant="invisible"
          size="small"
          style={{marginLeft: 'auto'}}
          aria-label="Stop execution"
        />
      ) : (
        <>
          {commandForTask ? (
            <IconButton
              aria-label="Configure command"
              icon={PencilIcon}
              variant="invisible"
              onClick={handleEditCommand}
              ref={editCommandRef}
            />
          ) : (
            <IconButton
              aria-label="Add command"
              icon={PlusIcon}
              variant="invisible"
              onClick={handleEditCommand}
              ref={editCommandRef}
            />
          )}
          {!commandExecuted && commandForTask && (
            <IconButton
              aria-label="Execute command"
              icon={PlayIcon}
              variant="invisible"
              onClick={() => executeCommand(commandForTask, task)}
            />
          )}
          {showFixABuildButton && (
            <div className="ml-auto">
              {fixABuildLoading ? (
                <Spinner size="small" className="ml-auto" />
              ) : (
                <IconButton
                  icon={ToolsIcon}
                  aria-label="Fix command"
                  onClick={handleFixABuildClick}
                  variant="invisible"
                  ref={fixBuildRef ?? null}
                />
              )}
            </div>
          )}
          {exitCode != null && commandForTask && (
            <>
              <IconButton aria-label="Clear output" icon={TrashIcon} variant="invisible" onClick={clearTask} />
              <IconButton
                icon={SyncIcon}
                onClick={() => {
                  executeCommand(commandForTask, task)
                }}
                variant="invisible"
                aria-label="Re-run"
              />
            </>
          )}
        </>
      )}
    </div>
  )
}

export default TerminalCommandActions
