import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import type {DiffHunkReference, TerminalLogReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {
  CheckCircleFillIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  SquareFillIcon,
  ToolsIcon,
  XCircleFillIcon,
} from '@primer/octicons-react'
import {Box, Button, IconButton, Spinner} from '@primer/react'
import {Octicon} from '@primer/react/deprecated'
import {formatPatch} from 'diff'
import type React from 'react'
import {useMemo, useRef} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useTerminalContext} from '../contexts/TerminalContext'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from '../contexts/WorkspaceEditorUIContext'
import {useAnalytics} from '../telemetry/use-analytics'
import type {CommandResult} from '../utilities/terminal-reducer'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'

interface HistoryItemProps {
  toggleCollapse: (command: CommandResult) => void
  command: CommandResult
  isLastItem: boolean
}

const FIX_BUILD_PROMPT =
  'Look at the attached terminal log output, as well as the attached changes to files in this repository. Then, make a plan and analyze failure in the log by looking at related files either in this repo, or attached as references to explain the error. What is the error and how can it be fixed?'
const HistoryItem: React.FC<HistoryItemProps> = ({toggleCollapse, command, isLastItem}) => {
  const {stopCommand} = useTerminalContext()
  const {repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const {getChangedFiles} = useFilesContext()
  const fixBuildRef = useRef<HTMLButtonElement>(null)
  const sendEvent = useAnalytics()

  const manager = useChatManager()
  const dispatch = useWorkspaceEditorUIDispatch()
  const state = useWorkspaceEditorUIState()
  const {buildTask, exitCode, collapsed, output, loading} = command

  const showFixABuildButton = !!exitCode && !!output

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
  }, [getChangedFiles, output, pullRequest.id, repo.id, repo.name, repo.ownerLogin, showFixABuildButton])

  if (command === undefined) {
    return <></>
  }

  const attachOutputToChat = () => {
    if (!showFixABuildButton || !references) return
    const {logRef, changedFilesRefs} = references
    if (state.rightPanel !== RightPanelType.Chat) {
      dispatch({
        type: 'TOGGLE_RIGHT_PANEL',
        rightPanel: RightPanelType.Chat,
        rightPanelButton: fixBuildRef.current ?? undefined,
      })
    }

    const referencesToSend = [logRef, ...(changedFilesRefs || [])]
    manager.sendChatMessage(null, FIX_BUILD_PROMPT, referencesToSend)
    sendEvent('terminal.fix_build', {
      buildTask,
      referenceCount: referencesToSend.length,
      referenceCharacterCount:
        logRef.output.length + (changedFilesRefs?.reduce((acc, ref) => acc + ref.diff.length, 0) || 0),
    })
  }

  const renderLoadingState = () => (
    <Box
      sx={{
        display: 'flex',
        gap: 2,
        alignItems: 'center',
        p: 3,
        color: 'fg.muted',
        fontFamily: 'var(--fontStack-sansSerif)',
      }}
    >
      <Spinner size="small" /> Loading
    </Box>
  )

  const maybeBorderBottomClass = isLastItem ? '' : 'border-bottom'

  const renderOutput = () => {
    return <pre className={`${maybeBorderBottomClass} text-mono px-3 py-2`}>{output}</pre>
  }

  const innerContent = collapsed ? null : loading ? renderLoadingState() : renderOutput()

  return (
    <div key={command.id} className="d-flex flex-column">
      <div
        className={`${maybeBorderBottomClass} d-flex flex-items-center gap-2 px-2 py-1 position-sticky top-0 bgColor-muted`}
      >
        <IconButton
          aria-label={collapsed ? 'Expand' : 'Collapse'}
          icon={collapsed ? ChevronRightIcon : ChevronDownIcon}
          variant="invisible"
          size="small"
          onClick={() => toggleCollapse(command)}
        />
        {exitCode === 0 ? (
          <Octicon icon={CheckCircleFillIcon} className="fgColor-success" />
        ) : exitCode !== null ? (
          <Octicon icon={XCircleFillIcon} className="fgColor-danger" />
        ) : (
          <Spinner size="small" />
        )}
        <span className="text-bold f6">{buildTask}</span>
        {!loading && exitCode === null ? (
          <Button
            onClick={() => stopCommand(command)}
            variant="invisible"
            size="small"
            leadingVisual={SquareFillIcon}
            style={{marginLeft: 'auto'}}
          >
            Stop
          </Button>
        ) : null}
        {showFixABuildButton && (
          <Button
            leadingVisual={ToolsIcon}
            onClick={attachOutputToChat}
            variant="invisible"
            className="ml-auto"
            ref={fixBuildRef ?? null}
          >
            Fix
          </Button>
        )}
      </div>
      {innerContent}
    </div>
  )
}

export default HistoryItem
