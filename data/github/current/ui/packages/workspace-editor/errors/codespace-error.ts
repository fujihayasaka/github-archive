import type {CodespaceStateInfo} from '../utilities/workspace-editor-types'
import {BaseError} from './base-error'

// Codespace related error type.
export class CodespaceError extends BaseError {
  public override readonly errorType: string = 'CodespaceError'

  constructor(
    error?: Error | string,
    public readonly codespaceState?: CodespaceStateInfo,
  ) {
    super(error)
    this.name = 'CodespaceError'
  }
}
