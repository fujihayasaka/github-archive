import type {RemoteProvider} from '@github/codespaces-lsp'
import {useCallback, useState} from 'react'

import type {PortForwarder} from '../utilities/workspace-editor-types'

/**
 * The following code is the VS Code url matcher that is used for detecting ports in Codespaces.
 */
const terminalCodesRegex =
  // eslint-disable-next-line no-control-regex, no-useless-escape
  /(?:\u001B|\u009B)[\[\]()#;?]*(?:(?:(?:[a-zA-Z0-9]*(?:;[a-zA-Z0-9]*)*)?\u0007)|(?:(?:\d{1,4}(?:;\d{0,4})*)?[0-9A-PR-TZcf-ntqry=><~]))/g
/**
 * Local server url pattern matching following urls:
 * http://localhost:3000/ - commonly used across multiple frameworks
 * https://127.0.0.1:5001/ - ASP.NET
 * http://:8080 - Beego Golang
 * http://0.0.0.0:4000 - Elixir Phoenix
 */
const localUrlRegex =
  // eslint-disable-next-line no-useless-escape
  /\b\w{2,20}:\/\/(?:localhost|127\.0\.0\.1|0\.0\.0\.0|:\d{2,5})[\w\-\.\~:\/\?\#[\]\@!\$&\(\)\*\+\,\;\=]*/gim
const extractPortRegex = /(localhost|127\.0\.0\.1|0\.0\.0\.0):(\d{1,5})/
/**
 * https://github.com/microsoft/vscode-remote-release/issues/3949
 */
const localPythonServerRegex = /HTTP\son\s(127\.0\.0\.1|0\.0\.0\.0)\sport\s(\d+)/

const urlFinder = (
  data: string,
):
  | {
      port: number
      protocol: string
    }
  | undefined => {
  // strip ANSI terminal codes
  data = data.replace(terminalCodesRegex, '')
  const urlMatches = data.match(localUrlRegex) || []
  if (urlMatches && urlMatches.length > 0) {
    for (const match of urlMatches) {
      // check if valid url
      let serverUrl
      try {
        // eslint-disable-next-line no-restricted-syntax
        serverUrl = new URL(match)
      } catch {
        // Not a valid URL
      }
      if (serverUrl) {
        // check if the port is a valid integer value
        const portMatch = match.match(extractPortRegex)
        const port = parseFloat(serverUrl.port ? serverUrl.port : portMatch && portMatch[2] ? portMatch[2] : 'NaN')
        if (!isNaN(port) && Number.isInteger(port) && port > 0 && port <= 65535) {
          // remove colon at the end of protocol
          const protocol = serverUrl.protocol.replace(':', '')
          return {port, protocol}
        }
      }
    }
  } else {
    // Try special python case
    const pythonMatch = data.match(localPythonServerRegex)
    if (pythonMatch && pythonMatch[2] && pythonMatch.length === 3) {
      return {
        protocol: 'http',
        port: parseInt(pythonMatch[2], 10),
      }
    }
  }
  return
}

export function usePortForwarding(remoteProvider?: RemoteProvider): PortForwarder {
  const [forwardedUrl, setForwardedUrl] = useState<string>('')

  const dataScraper = useCallback(
    (data: string) => {
      if (remoteProvider) {
        const url = urlFinder(data)
        if (url) {
          // We don't want to lock the thread on this, so we'll just fire and forget
          // eslint-disable-next-line github/no-then
          remoteProvider.forwardPort(url.port, url.protocol).then(port => {
            if (port.portForwardingUris) {
              setForwardedUrl(
                (port.portForwardingUris && port.portForwardingUris[port.portForwardingUris.length - 1]) || '',
              )
            }
          })
        }
      }
    },
    [remoteProvider],
  )

  return {
    dataScraper,
    forwardedUrl,
  }
}
