import type {CodespaceStateInfo} from '../utilities/workspace-editor-types'
import {BaseError} from './base-error'

// Codespace related error type.
export class CodespaceError extends BaseError {
  public override readonly errorType: string = 'CodespaceError'

  declare readonly codespaceState?: CodespaceStateInfo

  constructor(error?: Error | string, codespaceState?: CodespaceStateInfo) {
    super(error)
    this.name = 'CodespaceError'
    this.codespaceState = codespaceState
  }
}

export class CodespaceNotInTargetStateError extends CodespaceError {
  public override readonly errorType: string = 'CodespaceNotInTargetStateError'

  constructor(targetState: CodespaceStateInfo, currentState?: CodespaceStateInfo) {
    super(`Codespace is not in the target state: '${targetState}', current state is: '${currentState}'`, currentState)
    this.name = 'CodespaceNotInTargetStateError'
  }
}
