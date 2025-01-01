import {usePortForwarding} from '@github-ui/workspace-editor/hooks/use-port-forwarding'
import type {ITerminalOptions} from '@github-ui/workspace-editor/utilities/terminal-types'
import type {SshChannel} from '@microsoft/dev-tunnels-ssh'
import {createContext, useCallback, useContext, useEffect, useMemo, useReducer} from 'react'

import {
  clearHistory,
  type CommandResult,
  type CommandTask,
  type TerminalAction,
  terminalReducer,
  type TerminalState,
} from '../utilities/terminal-reducer'
import {useCodespaceContext} from './CodespaceContext'

export type TerminalContextData = {
  state: TerminalState
  dispatch: React.Dispatch<TerminalAction>
  stopCommand: (command: CommandResult) => void
  executeCommand: (command: string, task: CommandTask) => Promise<{exitCode?: number; output: string}>
  restartCommand: (command: CommandResult) => Promise<void>
  openTerminalChannel: (opts?: ITerminalOptions) => Promise<SshChannel>
}

export const TerminalContext = createContext<TerminalContextData | null>(null)

function initializeState(seed: Pick<TerminalState, 'codespaceData' | 'tasks' | 'previewUrl'>): TerminalState {
  return {
    isCollapsed: true,
    pane: 'terminal',
    history: clearHistory(),
    tasks: seed.tasks,
    codespaceData: seed.codespaceData,
    previewUrl: seed.previewUrl,
  }
}

export function TerminalContextProvider({children}: React.PropsWithChildren) {
  const {codespaceData} = useCodespaceContext()

  const {dataScraper, forwardedUrl} = usePortForwarding(codespaceData.remoteProvider)
  useEffect(() => {
    dispatch({type: 'SET_PREVIEW_URL', previewUrl: forwardedUrl})
  }, [forwardedUrl])

  const [state, dispatch] = useReducer(
    terminalReducer,
    {codespaceData, tasks: {}, previewUrl: forwardedUrl},
    initializeState,
  )

  useEffect(() => {
    dispatch({type: 'SET_CODESPACE_DATA', codespaceData})
    // codespaceData changes frequently, but we only really care when the state changes
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [codespaceData.codespaceState, codespaceData.isRecoveryContainer, codespaceData.permissionsStatus])

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
    async (command: string, task: CommandTask): Promise<{exitCode?: number; output: string}> => {
      const {remoteProvider, sessionPath} = validateSession()
      const result = await new Promise<{exitCode?: number; output: string}>(async resolve => {
        let output = ''

        dispatch({
          type: 'START_COMMAND',
          command: {
            command,
            task,
            output,
            collapsed: state.isCollapsed,
            exitCode: null,
            channel: null,
            loading: true,
            stopped: false,
            startTime: null,
            endTime: null,
          },
        })

        const channel = await remoteProvider.getCommandChannel()

        channel.onExitCode(({status}) => {
          const exitCode = status ?? 0
          dispatch({type: 'COMPLETE_COMMAND', task, exitCode})
          dispatch({type: 'SET_PREVIEW_URL', previewUrl: undefined})

          resolve({
            exitCode,
            output,
          })
        })

        const onConsoleData = (data: string) => {
          dataScraper(data)
          output += data
          dispatch({type: 'UPDATE_COMMAND', task, output})
        }

        channel.onStandardOutput(onConsoleData)
        channel.onErrorOutput(onConsoleData)

        channel.executeCommand(`cd ${sessionPath} && ${command}`)
        dispatch({type: 'UPDATE_COMMAND', task, loading: false, channel, startTime: new Date()})
      })
      return result
    },
    // we don't want to run execute command everytime the user collapses/expands the terminal
    // we don't include the `state.isCollapsed` in the dependencies list
    // eslint-disable-next-line react-hooks/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [dataScraper, validateSession],
  )

  const stopCommand = useCallback((command: CommandResult) => {
    if (command.channel) {
      command.channel.stop('INT')
      dispatch({
        type: 'UPDATE_COMMAND',
        task: command.task,
        stopped: true,
      })
      return
    }

    // If we attempt to stop the command as it's loading, we need to mark it as stopped and
    // clear the state so we show all of the action buttons before the channel is fully cleaned up
    if (command.loading) {
      dispatch({
        type: 'UPDATE_COMMAND',
        task: command.task,
        stopped: true,
        startTime: null,
        endTime: null,
        exitCode: 0,
        channel: null,
      })
    }
  }, [])

  const restartCommand = useCallback(
    async (command: CommandResult) => {
      stopCommand(command)
      await executeCommand(command.command, command.task)
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
    }),
    [state, executeCommand, stopCommand, restartCommand, openTerminalChannel],
  )

  return <TerminalContext.Provider value={value}>{children}</TerminalContext.Provider>
}

export function useTerminalContext() {
  const context = useContext(TerminalContext)
  if (!context) {
    throw new Error('useTerminalContext must be used within a TerminalContextProvider')
  }
  return context
}
