import {generateCommandStatusText} from '../generate-command-status-text'
import {clearTask, type CommandResult, CommandTask} from '../terminal-reducer'

describe('generateCommandStatusText', () => {
  it('should return "Canceled" if the command is stopped', () => {
    const command: CommandResult = {...clearTask(CommandTask.Build), stopped: true}
    const result = generateCommandStatusText(command, false, '', '')
    expect(result).toBe('Canceled')
  })

  it('should return "Connecting..." if the command is executed but not started', () => {
    const command: CommandResult = {...clearTask(CommandTask.Build)}
    const result = generateCommandStatusText(command, true, '', '')
    expect(result).toBe('Connecting...')
  })

  it('should return the command duration if the command is executed and started', () => {
    const command: CommandResult = {...clearTask(CommandTask.Build), startTime: new Date()}
    const result = generateCommandStatusText(command, true, '5s', '')
    expect(result).toBe('5s')
  })

  it('should return the command for the task if the command is not executed', () => {
    const command: CommandResult = {...clearTask(CommandTask.Build)}
    const result = generateCommandStatusText(command, false, '', 'Task Command')
    expect(result).toBe('Task Command')
  })

  it('should return undefined if the command is not executed and no command for the task is provided', () => {
    const command: CommandResult = {...clearTask(CommandTask.Build)}
    const result = generateCommandStatusText(command, false, '', undefined)
    expect(result).toBeUndefined()
  })
})
