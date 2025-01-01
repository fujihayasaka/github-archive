import type {IEnvironmentConfiguredArgs} from '@github/codespaces-ssh-tunneling'
import type {TunnelPort} from '@microsoft/dev-tunnels-contracts'
import type {SshChannel} from '@microsoft/dev-tunnels-ssh'
import type {Event} from 'vscode-jsonrpc'

export interface ITerminalOptions {
  term?: string
  cols?: number
  rows?: number
  pixelWidth?: number
  pixelHeight?: number
  keepAliveOnData?: boolean
}

export interface IRemoteProviderInternal {
  forwardPort(port: number, protocol: string): Promise<TunnelPort>
  getEnvironmentConfiguredEvent(): Event<IEnvironmentConfiguredArgs>
  getTerminalChannel(terminalOptions: ITerminalOptions): Promise<SshChannel>
}

export enum TerminalStatus {
  Connecting,
  Connected,
  Disconnected,
  Error,
}

export enum TerminalVisibility {
  Hidden,
  Visible,
}
