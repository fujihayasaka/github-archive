import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {useLocalStorage} from '@github-ui/use-safe-storage/local-storage'
import type {SshChannel} from '@microsoft/dev-tunnels-ssh'
import {createContext, useCallback, useContext, useEffect, useMemo, useReducer, useRef, useState} from 'react'

import {useFetchRepoTerminalTasks} from '../hooks/use-fetch-repo-terminal-tasks'
import {usePortForwarding} from '../hooks/use-port-forwarding'
import {useCodespaces} from '../lsp/use-codespaces'
import {useAnalytics} from '../telemetry/use-analytics'
import {
  type CommandResult,
  type TerminalAction,
  terminalReducer,
  type TerminalState,
} from '../utilities/terminal-reducer'
import {hasAnyCommands} from '../utilities/terminal-tasks'
import type {ITerminalOptions} from '../utilities/terminal-types'
import type {TerminalTasks, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {useCurrentPullRequest} from './CurrentPullRequestProvider'

export type TerminalContext = {
  state: TerminalState
  dispatch: React.Dispatch<TerminalAction>
  stopCommand: (command: CommandResult) => void
  executeCommand: (command: string, buildTask: string, stop?: boolean) => Promise<{exitCode?: number; output: string}>
  restartCommand: (command: CommandResult) => Promise<void>
  openTerminalChannel: (opts?: ITerminalOptions) => Promise<SshChannel>
}

const TerminalContext = createContext<TerminalContext | null>(null)

function initializeState(seed: Pick<TerminalState, 'codespaceData' | 'tasks' | 'previewUrl'>): TerminalState {
  return {
    terminalVisibility: 'hidden',
    pane: 'output',
    history: [] as CommandResult[],
    currentCommand: null,
    tasks: seed.tasks,
    codespaceData: seed.codespaceData,
    previewUrl: seed.previewUrl,
  }
}

function buildTasksStorageKey(org: string, repoName: string, entityId: string) {
  return `hadron-editor-terminal-tasks/${org}/${repoName}/${entityId}`
}

export function TerminalContextProvider({children}: React.PropsWithChildren) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {repo} = payload
  const {pullRequest} = useCurrentPullRequest()
  const codespaceData = useCodespaces(repo, pullRequest)
  const sendEvent = useAnalytics()

  const {fetchRepoTasks} = useFetchRepoTerminalTasks(codespaceData)

  const [localStorageTasks, setLocalStorageTasks] = useLocalStorage<TerminalTasks>(
    buildTasksStorageKey(repo.ownerLogin, repo.name, pullRequest.number),
    {},
  )

  const {dataScraper, forwardedUrl} = usePortForwarding(codespaceData.remoteProvider)
  useEffect(() => {
    dispatch({type: 'SET_PREVIEW_URL', previewUrl: forwardedUrl})
  }, [forwardedUrl])

  const [state, dispatch] = useReducer(
    terminalReducer,
    {codespaceData, tasks: localStorageTasks, previewUrl: forwardedUrl},
    initializeState,
  )

  useEffect(() => {
    dispatch({type: 'SET_CODESPACE_DATA', codespaceData})
    // codespaceData changes frequently, but we only really care when the state changes
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [codespaceData.codespaceState, codespaceData.isRecoveryContainer, codespaceData.permissionsStatus])

  const commandIdCounter = useRef(0)

  const generateUniqueId = () => {
    return commandIdCounter.current++
  }

  const validateSession = useCallback(() => {
    const remoteProvider = codespaceData.remoteProvider
    const sessionPath = codespaceData.codespaceInfo?.environment_data.connection.sessionPath
    if (!remoteProvider || !sessionPath) {
      throw new Error('Failed executing command')
    }
    return {remoteProvider, sessionPath}
  }, [codespaceData.remoteProvider, codespaceData.codespaceInfo?.environment_data.connection.sessionPath])

  const openTerminalChannel = useCallback(
    async (opts?: ITerminalOptions): Promise<SshChannel> => {
      if (!codespaceData.remoteProvider) {
        throw Error('Failed opening shell - remote provider not available')
      }

      const channel = await codespaceData.remoteProvider?.getTerminalChannel({...opts})

      channel?.onDataReceived(data => {
        dataScraper(data.toString('utf-8'))
      })

      return channel
    },
    [codespaceData.remoteProvider, dataScraper],
  )

  const executeCommand = useCallback(
    async (command: string, buildTask: string): Promise<{exitCode?: number; output: string}> => {
      const {remoteProvider, sessionPath} = validateSession()

      dispatch({
        type: 'TOGGLE_TERMINAL_VISIBILITY',
        terminalVisibility: 'visible',
      })

      const result = await new Promise<{exitCode?: number; output: string}>(async resolve => {
        const id = generateUniqueId()
        sendEvent('validation.task.start', {command_id: id, task_type: buildTask})
        let output = ''

        dispatch({
          type: 'START_COMMAND',
          command: {
            command,
            buildTask,
            output,
            id,
            collapsed: false,
            exitCode: null,
            channel: null,
            loading: true,
          },
        })

        const startTime = performance.now()

        const channel = await remoteProvider.getCommandChannel()

        sendEvent('validation.channel.created', {
          command_id: id,
          task_type: buildTask,
          time_elapsed_ms: performance.now() - startTime,
        })

        channel.onExitCode(({status}) => {
          const exitCode = status ?? 0
          dispatch({type: 'COMPLETE_COMMAND', id, exitCode})
          dispatch({type: 'SET_PREVIEW_URL', previewUrl: undefined})

          sendEvent('validation.task.end', {command_id: id, task_type: buildTask, exit_code: exitCode})
          resolve({
            exitCode,
            output,
          })
        })

        const onConsoleData = (data: string) => {
          dataScraper(data)
          output += data
          dispatch({type: 'UPDATE_COMMAND', id, output})
        }

        channel.onStandardOutput(onConsoleData)
        channel.onErrorOutput(onConsoleData)

        channel.executeCommand(`cd ${sessionPath} && ${command}`)
        dispatch({type: 'UPDATE_COMMAND', id, loading: false, channel})
      })
      return result
    },
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [dataScraper, validateSession],
  )

  const stopCommand = useCallback((command: CommandResult) => {
    if (command.channel) {
      command.channel.stop('INT')
    }
  }, [])

  const restartCommand = useCallback(
    async (command: CommandResult) => {
      stopCommand(command)
      await executeCommand(command.command, command.buildTask)
    },
    [executeCommand, stopCommand],
  )

  const value = useMemo(
    () => ({
      state,
      dispatch,
      executeCommand,
      openTerminalChannel,
      stopCommand,
      restartCommand,
      tasks: localStorageTasks ?? {},
      setTasks: setLocalStorageTasks,
    }),
    [state, executeCommand, stopCommand, restartCommand, localStorageTasks, setLocalStorageTasks, openTerminalChannel],
  )

  const [hasFetchedRepoTasks, setHasFetchedRepoTasks] = useState(false)

  // If we didn't have tasks in local storage, fetch them from the server
  const updateTasks = useCallback(async () => {
    // It's also possible that we already fetched, but the user deleted all the commands
    // and saved, so in that case also don't fetch again
    if (hasFetchedRepoTasks) {
      return
    }

    setHasFetchedRepoTasks(true)

    if (hasAnyCommands(localStorageTasks)) {
      return
    }

    const repoTasks = await fetchRepoTasks()
    if (!repoTasks) {
      return
    }

    dispatch({type: 'SET_TASKS', tasks: repoTasks})
  }, [hasFetchedRepoTasks, localStorageTasks, fetchRepoTasks])

  // Fetch tasks when the component mounts
  useEffect(() => {
    updateTasks()
  }, [updateTasks])

  // Any time tasks change (via the reducer), update local storage
  useEffect(() => {
    setLocalStorageTasks(state.tasks)
  }, [state.tasks, setLocalStorageTasks])

  return <TerminalContext.Provider value={value}>{children}</TerminalContext.Provider>
}

export function useTerminalContext() {
  const context = useContext(TerminalContext)
  if (!context) {
    throw new Error('useTerminalContext must be used within a TerminalContextProvider')
  }
  return context
}
