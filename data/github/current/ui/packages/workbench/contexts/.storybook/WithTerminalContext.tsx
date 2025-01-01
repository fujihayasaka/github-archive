import type {SshChannel} from '@microsoft/dev-tunnels-ssh/sshChannel'
import {action} from '@storybook/addon-actions'
import {useArgs} from '@storybook/preview-api'
import type {Decorator} from '@storybook/react'

import {CommandTask, type CommandResult, type TerminalState} from '../../utilities/terminal-reducer'
import {TerminalContext, type TerminalContextData} from '../TerminalContext'

export const withTerminalContext: Decorator = (Story, {args}) => {
  const [{}, updateArgs] = useArgs()

  const contextValue = {
    state: {
      history: {
        [CommandTask.Deploy]: {
          command: 'deploy',
          output: args.commandDeployOutput as string,
          exitCode: 0,
          task: CommandTask.Deploy,
          startTime: args.commandDeployStartTime as Date | null,
          endTime: args.commandDeployEndTime as Date | null,
          collapsed: false,
          stopped: args.commandDeployStopped as boolean,
          loading: args.commandDeployLoading as boolean,
        } satisfies Partial<CommandResult>,
      },
      codespaceData: {},
    } as unknown as TerminalState,
    dispatch: action('dispatch'),
    stopCommand: action('stopCommand'),
    executeCommand: async (command: string, task: CommandTask) => {
      action('executeCommand')()
      if (task === CommandTask.Deploy) {
        // Simulate a deploy command execution
        updateArgs({
          commandDeployOutput: 'Build in progress',
          commandDeployStartTime: new Date(),
          commandDeployEndTime: null,
          commandDeployStopped: false,
          commandDeployLoading: false,
        })
        setTimeout(() => {
          if (args.shouldBuildSucceed) {
            updateArgs({
              commandDeployOutput: 'Build success, Publish success',
              commandDeployStartTime: new Date(),
              commandDeployEndTime: new Date(),
              commandDeployStopped: true,
              commandDeployLoading: false,
            })
          } else {
            updateArgs({
              commandDeployOutput: 'Build success, Publish fail',
              commandDeployStartTime: new Date(),
              commandDeployEndTime: new Date(),
              commandDeployStopped: true,
              commandDeployLoading: false,
            })
          }
        }, 4000) // Simulate a delay for command execution
      }
      return Promise.resolve({output: ''})
    },
    restartCommand: () => Promise.resolve(),
    openTerminalChannel: () => Promise.resolve({} as SshChannel),
  } as TerminalContextData

  return (
    <TerminalContext.Provider value={contextValue}>
      <Story />
    </TerminalContext.Provider>
  )
}

export const terminalContextDecoratorArgTypes = {
  commandDeployOutput: {
    control: 'select',
    description: 'The output of the command',
    options: ['Empty', 'Build in progress', 'Build success, Publish fail', 'Build success, Publish success'],
    mapping: {
      Empty: '',
      'Build in progress': 'some output stuff here',
      'Build success, Publish fail': '[--Build: Complete--]',
      'Build success, Publish success':
        '[--Build: Complete--] [--Deployment: Complete--] https://app-username.github.app',
    },
    table: {
      category: 'TerminalContext',
    },
  },
  commandDeployStartTime: {
    control: 'date',
    description: 'The start time of the command',
    table: {
      category: 'TerminalContext',
    },
  },
  commandDeployEndTime: {
    control: 'date',
    description: 'The end time of the command',
    table: {
      category: 'TerminalContext',
    },
  },
  shouldBuildSucceed: {
    control: 'boolean',
    description: 'Whether the build should succeed or fail',
    table: {
      category: 'TerminalContext',
    },
  },
  commandDeployStopped: {
    control: 'boolean',
    description: 'Whether the deploy command is stopped',
    table: {
      category: 'TerminalContext',
    },
  },
  commandDeployLoading: {
    control: 'boolean',
    description: 'Whether the deploy command is loading',
    table: {
      category: 'TerminalContext',
    },
  },
}

export const terminalContextDecoratorArgs = {
  commandDeployOutput: 'Empty',
  commandDeployStartTime: null,
  commandDeployEndTime: null,
  shouldBuildSucceed: true,
  commandDeployStopped: false,
  commandDeployLoading: false,
}
