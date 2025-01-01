import 'xterm/css/xterm.css'

import {WindowChangeRequestMessage} from '@github/codespaces-ssh-tunneling'
import {TerminalConnectingSpinner} from '@github-ui/workspace-editor/components/TerminalConnectingSpinner'
import {getColorFromCSSVar} from '@github-ui/workspace-editor/utilities/get-color-from-css-var'
import {TerminalStatus} from '@github-ui/workspace-editor/utilities/terminal-types'
import type {SshChannel} from '@microsoft/dev-tunnels-ssh'
import {useTheme} from '@primer/react'
import {FitAddon} from '@xterm/addon-fit'
import {useEffect, useMemo, useRef, useState} from 'react'
import type {ITheme} from 'xterm'
import {Terminal as XTerm} from 'xterm'

import {useTerminalContext} from '../contexts/TerminalContext'

export const Terminal = ({terminalRef}: {terminalRef: React.RefObject<HTMLDivElement>}) => {
  const {
    state: {isCollapsed, pane, codespaceData},
    openTerminalChannel,
  } = useTerminalContext()
  const {theme} = useTheme() ?? {theme: {colors: {}}}
  // States
  const [terminalStatus, setTerminalStatus] = useState<TerminalStatus>(TerminalStatus.Connecting)

  // References
  const xtermRef = useRef<XTerm | null>(null)
  const channelRef = useRef<SshChannel | null>(null)
  const fitAddonRef = useRef<FitAddon | null>(null)
  const terminalInitialized = useRef(false)

  // Xterm theme handler
  const xtermTheme: ITheme = useMemo(
    () => ({
      foreground: getColorFromCSSVar(theme?.colors.fg.default ?? ''),
      background: getColorFromCSSVar(theme?.colors.canvas.default),
      cursor: getColorFromCSSVar(theme?.colors.accent.fg),
      cursorAccent: getColorFromCSSVar(theme?.colors.accent.fg ?? ''),
      selectionBackground: getColorFromCSSVar(theme?.colors.accent.fg ?? '', 0.2),
      selectionInactiveBackground: getColorFromCSSVar(theme?.colors.accent.fg, 0.07),
      black: getColorFromCSSVar(theme?.colors.ansi.black),
      brightBlack: getColorFromCSSVar(theme?.colors.ansi.blackBright),
      white: getColorFromCSSVar(theme?.colors.ansi.white),
      brightWhite: getColorFromCSSVar(theme?.colors.ansi.whiteBright),
      red: getColorFromCSSVar(theme?.colors.ansi.red),
      brightRed: getColorFromCSSVar(theme?.colors.ansi.redBright),
      green: getColorFromCSSVar(theme?.colors.ansi.green),
      brightGreen: getColorFromCSSVar(theme?.colors.ansi.greenBright),
      yellow: getColorFromCSSVar(theme?.colors.ansi.yellow),
      brightYellow: getColorFromCSSVar(theme?.colors.ansi.yellowBright),
      blue: getColorFromCSSVar(theme?.colors.ansi.blue),
      brightBlue: getColorFromCSSVar(theme?.colors.ansi.blueBright),
      magenta: getColorFromCSSVar(theme?.colors.ansi.magenta),
      brightMagenta: getColorFromCSSVar(theme?.colors.ansi.magentaBright),
      cyan: getColorFromCSSVar(theme?.colors.ansi.cyan),
      brightCyan: getColorFromCSSVar(theme?.colors.ansi.cyanBright),
    }),
    [theme],
  )

  const terminalResizeCallback = () => {
    try {
      fitAddonRef.current?.fit()
      const windowChangeMessage = new WindowChangeRequestMessage(
        xtermRef.current?.cols ?? 0,
        xtermRef.current?.rows ?? 0,
        0,
        0,
      )
      channelRef.current?.request(windowChangeMessage)
    } catch {
      // Resize failed
    }
  }

  // const reportTerminalCommandRunDebounced = debounce((data: string) => {
  //   if (data.includes('\n') || data.includes('\r')) {
  //     sendEvent('validation.terminal.run')
  //   }
  // }, 1000)

  // Initialize
  useEffect(() => {
    let resizeObserver: ResizeObserver | undefined = undefined

    const connectTerminal = async () => {
      try {
        xtermRef.current = new XTerm({
          theme: xtermTheme,
        })
        fitAddonRef.current = new FitAddon()
        xtermRef.current.loadAddon(fitAddonRef.current)

        channelRef.current = await openTerminalChannel({
          term: 'xterm',
          cols: xtermRef.current.cols,
          rows: xtermRef.current.rows,
          keepAliveOnData: true,
        })
        channelRef.current.onDataReceived((data: Buffer) => {
          const dataString = data.toString('utf-8')
          xtermRef.current?.write(dataString)
        })
        xtermRef.current.onData(data => {
          // if data contains a newline or carriage return, consider it as a command run
          channelRef.current?.send(Buffer.from(data))

          // reportTerminalCommandRunDebounced(data)
        })
        channelRef.current.onClosed(() => {
          dispose()
        })

        if (terminalRef.current) {
          resizeObserver = new ResizeObserver(terminalResizeCallback)
          resizeObserver.observe(terminalRef.current)
        }
        if (terminalRef.current) {
          xtermRef.current.open(terminalRef.current)
          fitAddonRef.current.fit()
        }

        setTerminalStatus(TerminalStatus.Connected)
      } catch {
        // TODO: Add telemetry/logging to capture when the terminal errors out on connection

        // If the terminal fails to connect, we need to reset the state so that we can try connecting again
        // if the codespace or terminal status changes
        terminalInitialized.current = false
        setTerminalStatus(TerminalStatus.Connecting)
      }
    }

    if (
      terminalStatus === TerminalStatus.Connecting &&
      !terminalInitialized.current &&
      pane === 'terminal' &&
      codespaceData?.codespaceState === 'ready'
    ) {
      terminalInitialized.current = true
      connectTerminal()
    }
    // the `sendEvent()` function always changes so we don't want to include it into the dependencies list
  }, [openTerminalChannel, terminalStatus, xtermTheme, pane, terminalRef, codespaceData.codespaceState])

  useEffect(() => {
    if (!isCollapsed && terminalStatus === TerminalStatus.Connected) {
      terminalResizeCallback()
    }
  }, [isCollapsed, terminalStatus, pane])

  // Dispose
  const dispose = () => {
    if (fitAddonRef.current) {
      fitAddonRef.current.dispose()
    }
    if (channelRef.current) {
      channelRef.current.dispose()
    }
    if (xtermRef.current) {
      xtermRef.current.dispose()
    }

    // Reset the terminal state so we can recreate it
    terminalInitialized.current = false
    setTerminalStatus(TerminalStatus.Connecting)
  }

  return (
    <>
      <TerminalConnectingSpinner terminalStatus={terminalStatus} />
      <div ref={terminalRef} id="terminal-container" className="height-full overflow-hidden" />
    </>
  )
}
